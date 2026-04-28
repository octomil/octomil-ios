// Pure-Swift TAR reader.
//
// Reads an uncompressed ``.tar`` file and yields each member's
// header + data via a callback. Supports the GNU long-name
// extension (``L`` typeflag) and PAX extended headers (``x`` /
// ``g`` typeflag) so Kokoro and other multi-file release archives
// extract cleanly without ``/usr/bin/tar``.
//
// The format is a sequence of 512-byte blocks: header, data
// (rounded up to 512), header, data, ... terminated by two empty
// blocks. See https://www.gnu.org/software/tar/manual/html_node/Standard.html
//
// Only the metadata strictly needed for materialization is parsed
// (name, size, typeflag); ownership/mtime/checksum bits are
// ignored. Symlink and hardlink members are reported via
// ``Entry.kind`` so the caller can choose to drop them.

import Foundation

public enum TarError: Error, CustomStringConvertible {
    case truncated
    case malformedHeader(String)
    case unsupportedEntry(String)

    public var description: String {
        switch self {
        case .truncated: return "TAR: archive truncated mid-entry"
        case let .malformedHeader(detail): return "TAR: malformed header — \(detail)"
        case let .unsupportedEntry(detail): return "TAR: unsupported entry — \(detail)"
        }
    }
}

public struct TarEntry {
    public enum Kind {
        case file
        case directory
        case symbolicLink(target: String)
        case hardLink(target: String)
        case other(typeflag: UInt8)
    }

    public let name: String
    public let size: Int64
    public let kind: Kind
    public let mode: UInt32
}

public enum TarReader {
    /// Iterate every entry in the uncompressed TAR file at
    /// ``url``. ``handler`` receives the header AND a closure that,
    /// when called, yields the entry's payload bytes (in 64KB
    /// chunks). The handler MUST drain the payload before
    /// returning — the next iteration relies on file-handle
    /// position landing exactly at the start of the following
    /// header block.
    public static func read(
        from url: URL,
        handler: (TarEntry, (_ chunk: (Data) throws -> Void) throws -> Void) throws -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var pendingLongName: String? = nil

        while true {
            let header = try readBlock(handle)
            if header == nil { return } // EOF
            let block = header!
            // Two consecutive empty blocks mark end-of-archive.
            if block.allSatisfy({ $0 == 0 }) {
                let next = try readBlock(handle)
                if next == nil || next!.allSatisfy({ $0 == 0 }) {
                    return
                }
                // Single empty block in middle of archive — keep reading.
                continue
            }

            let typeflag = block[156]
            let storedName = parseString(block, offset: 0, length: 100)
            let size = try parseOctal(block, offset: 124, length: 12)
            let mode = UInt32(try parseOctal(block, offset: 100, length: 8))
            let dataBlocks = (size + 511) / 512
            let dataBytes = Int(dataBlocks * 512)

            // GNU long-name (typeflag 'L'): the entry's name is in
            // the data of THIS pseudo-entry; the real entry follows.
            if typeflag == 0x4C { // 'L'
                let payload = try readExact(handle, count: dataBytes)
                let trimmed = payload.prefix(Int(size))
                pendingLongName = String(decoding: trimmed.filter { $0 != 0 }, as: UTF8.self)
                continue
            }
            // PAX extended headers (typeflag 'x' / 'g'): skip the
            // payload; we don't honor extended attrs but must
            // advance the cursor past them.
            if typeflag == 0x78 || typeflag == 0x67 { // 'x' or 'g'
                _ = try readExact(handle, count: dataBytes)
                continue
            }

            let name: String
            if let long = pendingLongName {
                name = long
                pendingLongName = nil
            } else {
                // ustar prefix + name composition.
                let prefix = parseString(block, offset: 345, length: 155)
                name = prefix.isEmpty ? storedName : "\(prefix)/\(storedName)"
            }

            let kind: TarEntry.Kind
            switch typeflag {
            case 0, 0x30: kind = .file              // '\0' or '0'
            case 0x35: kind = .directory             // '5'
            case 0x32:                                // '2' symlink
                let target = parseString(block, offset: 157, length: 100)
                kind = .symbolicLink(target: target)
            case 0x31:                                // '1' hardlink
                let target = parseString(block, offset: 157, length: 100)
                kind = .hardLink(target: target)
            default:
                kind = .other(typeflag: typeflag)
            }

            let entry = TarEntry(name: name, size: size, kind: kind, mode: mode)

            // Track how many bytes the handler actually drained so
            // we can advance past unread payload + padding.
            var consumed: Int64 = 0
            try handler(entry) { chunk in
                let remaining = size - consumed
                if remaining <= 0 { return }
                let chunkSize: Int64 = 64 * 1024
                let toRead = min(chunkSize, remaining)
                let data = handle.readData(ofLength: Int(toRead))
                if data.count != Int(toRead) {
                    throw TarError.truncated
                }
                consumed += Int64(data.count)
                try chunk(data)
            }
            // Skip remaining payload (handler may have ignored
            // some entries) + zero padding to next 512-byte block.
            let unread = Int(size - consumed)
            if unread > 0 {
                let _ = try readExact(handle, count: unread)
            }
            let padding = Int(dataBlocks * 512 - size)
            if padding > 0 {
                _ = try readExact(handle, count: padding)
            }
        }
    }

    // MARK: - block helpers

    private static func readBlock(_ handle: FileHandle) throws -> [UInt8]? {
        let data = handle.readData(ofLength: 512)
        if data.isEmpty { return nil }
        if data.count != 512 {
            throw TarError.truncated
        }
        return Array(data)
    }

    private static func readExact(_ handle: FileHandle, count: Int) throws -> Data {
        var collected = Data()
        collected.reserveCapacity(count)
        while collected.count < count {
            let chunk = handle.readData(ofLength: count - collected.count)
            if chunk.isEmpty {
                throw TarError.truncated
            }
            collected.append(chunk)
        }
        return collected
    }

    private static func parseString(_ block: [UInt8], offset: Int, length: Int) -> String {
        let slice = block[offset..<offset + length]
        let nullTerminated = slice.prefix { $0 != 0 }
        return String(decoding: nullTerminated, as: UTF8.self)
    }

    /// TAR octal fields are NUL- or space-terminated ASCII octal.
    /// Some archives (large files) use a binary-encoded extension
    /// where the high bit of byte 0 is set; supported here.
    private static func parseOctal(_ block: [UInt8], offset: Int, length: Int) throws -> Int64 {
        let slice = Array(block[offset..<offset + length])
        if let first = slice.first, first & 0x80 != 0 {
            // base-256 binary big-endian — drop sign bit on first byte.
            var value: Int64 = Int64(first & 0x7F)
            for byte in slice.dropFirst() {
                value = (value << 8) | Int64(byte)
            }
            return value
        }
        let trimmed = slice.prefix { $0 != 0 && $0 != 0x20 }
        let str = String(decoding: trimmed, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        if str.isEmpty { return 0 }
        guard let value = Int64(str, radix: 8) else {
            throw TarError.malformedHeader("non-octal numeric field \(str.debugDescription)")
        }
        return value
    }
}

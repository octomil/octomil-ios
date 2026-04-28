// Streaming gzip decompressor on top of Apple's Compression
// framework (``COMPRESSION_ZLIB`` is raw zlib/deflate; gzip is
// the same compressor with a small header + footer wrapper).
//
// We strip the 10-byte gzip header + optional name/comment fields
// + 8-byte trailer manually, then feed the deflate body through
// ``compression_stream``. This avoids depending on a third-party
// gzip library and works identically on macOS / iOS.

import Compression
import Foundation

public enum GzipError: Error, CustomStringConvertible {
    case malformedHeader(String)
    case decompressFailed
    case unexpectedEndOfInput

    public var description: String {
        switch self {
        case let .malformedHeader(msg): return "gzip: malformed header — \(msg)"
        case .decompressFailed: return "gzip: decompression failed"
        case .unexpectedEndOfInput: return "gzip: input ended before end-of-stream"
        }
    }
}

public enum GzipDecompressor {
    public static func decompress(from inputURL: URL, to outputURL: URL) throws {
        // Read the whole file. Recipes we ship are tens of MB; if we
        // need to grow the SDK to handle multi-GB tarballs we'll
        // refactor to stream from disk.
        let raw = try Data(contentsOf: inputURL)
        let payload = try stripGzipFraming(raw)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        let bufferSize = 64 * 1024
        let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dest.deallocate() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }

        var status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw GzipError.decompressFailed }
        defer { compression_stream_destroy(stream) }

        try payload.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) in
            let src = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            stream.pointee.src_ptr = src
            stream.pointee.src_size = payload.count
            stream.pointee.dst_ptr = dest
            stream.pointee.dst_size = bufferSize

            while true {
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 {
                    let chunk = Data(bytes: dest, count: produced)
                    try handle.write(contentsOf: chunk)
                    stream.pointee.dst_ptr = dest
                    stream.pointee.dst_size = bufferSize
                }
                switch status {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return
                default:
                    throw GzipError.decompressFailed
                }
            }
        }
    }

    /// Strip the gzip header (10 bytes minimum + optional name /
    /// comment / extra fields) and 8-byte trailer, returning the
    /// raw deflate payload.
    private static func stripGzipFraming(_ data: Data) throws -> Data {
        guard data.count >= 18 else {
            throw GzipError.malformedHeader("input shorter than gzip envelope")
        }
        guard data[0] == 0x1F, data[1] == 0x8B else {
            throw GzipError.malformedHeader("missing gzip magic 1F 8B")
        }
        guard data[2] == 0x08 else {
            throw GzipError.malformedHeader("compression method != deflate")
        }
        let flags = data[3]
        var offset = 10 // fixed header
        // FEXTRA (bit 2): two-byte length + extra data
        if flags & 0x04 != 0 {
            guard data.count >= offset + 2 else {
                throw GzipError.malformedHeader("FEXTRA truncated")
            }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME (bit 3): null-terminated name
        if flags & 0x08 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1 // consume the NUL
        }
        // FCOMMENT (bit 4): null-terminated comment
        if flags & 0x10 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC (bit 1): 2-byte header CRC
        if flags & 0x02 != 0 {
            offset += 2
        }
        let trailerLength = 8
        guard offset + trailerLength <= data.count else {
            throw GzipError.unexpectedEndOfInput
        }
        return data.subdata(in: offset..<data.count - trailerLength)
    }
}

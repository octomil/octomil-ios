// Streaming BZ2 decompressor on top of the system libbz2.
//
// Both macOS and iOS SDKs ship ``libbz2.tbd`` and the matching
// ``bzlib.h`` header; the ``COctomilBZ2`` system library target
// surfaces the C API here. The Materializer composes this with a
// pure-Swift TAR reader so the runtime can extract Kokoro-style
// ``.tar.bz2`` archives without a subprocess (iOS forbids one and
// has no ``/usr/bin/tar`` anyway).

import COctomilBZ2
import Foundation

public enum BZ2Error: Error, CustomStringConvertible {
    case initFailed(Int32)
    case decompressFailed(Int32)
    case unexpectedEndOfInput

    public var description: String {
        switch self {
        case let .initFailed(code):
            return "BZ2_bzDecompressInit failed with code \(code)"
        case let .decompressFailed(code):
            return "BZ2_bzDecompress failed with code \(code)"
        case .unexpectedEndOfInput:
            return "BZ2: input ended before stream end marker"
        }
    }
}

/// Decompresses a single ``.bz2`` file into another file on disk.
/// Streams via 64KB input/output buffers so memory usage is bounded
/// regardless of archive size.
public enum BZ2Decompressor {
    public static func decompress(from inputURL: URL, to outputURL: URL) throws {
        // Make sure the destination's parent exists; tar fixtures
        // typically write next to the artifact dir.
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let inHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? inHandle.close() }
        let outHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outHandle.close() }

        var stream = bz_stream()
        let initResult = BZ2_bzDecompressInit(&stream, 0, 0)
        guard initResult == BZ_OK else {
            throw BZ2Error.initFailed(initResult)
        }
        defer { _ = BZ2_bzDecompressEnd(&stream) }

        let inBufSize = 64 * 1024
        let outBufSize = 64 * 1024
        var inBuf = [UInt8](repeating: 0, count: inBufSize)
        var outBuf = [UInt8](repeating: 0, count: outBufSize)
        var streamEnd = false

        while !streamEnd {
            let inputData = inHandle.readData(ofLength: inBufSize)
            if inputData.isEmpty {
                // libbz2 needs more input but the file is exhausted
                // before BZ_STREAM_END — treat as truncated archive.
                throw BZ2Error.unexpectedEndOfInput
            }
            // Copy into our Swift-managed buffer so we can hand a
            // mutable pointer to bzlib.
            _ = inBuf.withUnsafeMutableBufferPointer { dest in
                inputData.copyBytes(to: dest, from: 0..<inputData.count)
            }

            try inBuf.withUnsafeMutableBufferPointer { inPtr in
                stream.next_in = UnsafeMutableRawPointer(inPtr.baseAddress!).assumingMemoryBound(to: CChar.self)
                stream.avail_in = UInt32(inputData.count)

                while stream.avail_in > 0 || streamEnd == false {
                    let result: Int32 = outBuf.withUnsafeMutableBufferPointer { outPtr in
                        stream.next_out = UnsafeMutableRawPointer(outPtr.baseAddress!).assumingMemoryBound(to: CChar.self)
                        stream.avail_out = UInt32(outBufSize)
                        return BZ2_bzDecompress(&stream)
                    }
                    let produced = outBufSize - Int(stream.avail_out)
                    if produced > 0 {
                        let data = Data(bytes: outBuf, count: produced)
                        try outHandle.write(contentsOf: data)
                    }
                    if result == BZ_STREAM_END {
                        streamEnd = true
                        break
                    }
                    if result != BZ_OK {
                        throw BZ2Error.decompressFailed(result)
                    }
                    if stream.avail_in == 0, produced == 0 {
                        // Need more input from outer loop.
                        break
                    }
                }
            }
        }
    }
}

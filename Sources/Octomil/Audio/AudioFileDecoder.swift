import AVFoundation
import Foundation

/// Decodes audio files into 16 kHz mono `Float` PCM samples suitable for
/// speech-to-text engines (Whisper, sherpa-onnx, etc.).
///
/// Supported container formats include WAV, MP3, M4A, CAF, AIFF, and anything
/// else that `AVAudioFile` / `AVAudioConverter` can handle on the current OS.
///
/// ## Usage
///
/// ```swift
/// let decoder = AudioFileDecoder()
/// let samples = try decoder.decode(data: wavData) // [Float] 16 kHz mono
/// ```
public struct AudioFileDecoder: Sendable {

    /// Target sample rate expected by speech engines.
    public static let targetSampleRate: Double = 16_000

    public init() {}

    // MARK: - Decode from Data

    /// Decode audio `Data` into 16 kHz mono `Float` samples.
    ///
    /// The data is written to a temporary file so that `AVAudioFile` can open it.
    /// The temporary file is deleted after decoding.
    ///
    /// - Parameter data: Raw audio file bytes (WAV, MP3, M4A, etc.).
    /// - Returns: An array of `Float` samples in the range [-1, 1] at 16 kHz.
    /// - Throws: `AudioDecoderError` if the audio cannot be decoded.
    public func decode(data: Data) throws -> [Float] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("audio")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try decode(url: tempURL)
    }

    // MARK: - Decode from URL

    /// Decode an audio file at the given URL into 16 kHz mono `Float` samples.
    ///
    /// - Parameter url: File URL of the audio file.
    /// - Returns: An array of `Float` samples in the range [-1, 1] at 16 kHz.
    /// - Throws: `AudioDecoderError` if the audio cannot be decoded.
    public func decode(url: URL) throws -> [Float] {
        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: url)
        } catch {
            throw AudioDecoderError.cannotOpenFile(url: url, underlying: error)
        }

        let sourceFormat = sourceFile.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioDecoderError.cannotCreateTargetFormat
        }

        // If the source is already 16 kHz mono Float32, read directly.
        if sourceFormat.sampleRate == Self.targetSampleRate
            && sourceFormat.channelCount == 1
            && sourceFormat.commonFormat == .pcmFormatFloat32
        {
            return try readAllSamples(from: sourceFile, format: sourceFormat)
        }

        // Otherwise, convert via AVAudioConverter.
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioDecoderError.converterCreationFailed(
                sourceSampleRate: sourceFormat.sampleRate,
                sourceChannels: sourceFormat.channelCount
            )
        }

        // Estimate output frame count after sample rate conversion.
        let ratio = Self.targetSampleRate / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(sourceFile.length) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: estimatedFrames
        ) else {
            throw AudioDecoderError.bufferAllocationFailed(frames: estimatedFrames)
        }

        // Read the entire source into a buffer.
        let sourceFrameCount = AVAudioFrameCount(sourceFile.length)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: sourceFrameCount
        ) else {
            throw AudioDecoderError.bufferAllocationFailed(frames: sourceFrameCount)
        }

        do {
            try sourceFile.read(into: sourceBuffer)
        } catch {
            throw AudioDecoderError.readFailed(underlying: error)
        }

        // Convert.
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw AudioDecoderError.conversionFailed(underlying: conversionError)
        }

        guard status != .error else {
            throw AudioDecoderError.conversionFailed(underlying: nil)
        }

        // Extract Float samples from the output buffer.
        guard let channelData = outputBuffer.floatChannelData else {
            throw AudioDecoderError.noChannelData
        }

        let frameCount = Int(outputBuffer.frameLength)
        let pointer = channelData[0]
        return Array(UnsafeBufferPointer(start: pointer, count: frameCount))
    }

    // MARK: - Private

    private func readAllSamples(
        from file: AVAudioFile,
        format: AVAudioFormat
    ) throws -> [Float] {
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw AudioDecoderError.bufferAllocationFailed(frames: frameCount)
        }

        do {
            try file.read(into: buffer)
        } catch {
            throw AudioDecoderError.readFailed(underlying: error)
        }

        guard let channelData = buffer.floatChannelData else {
            throw AudioDecoderError.noChannelData
        }

        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))
    }
}

// MARK: - Errors

/// Errors that can occur during audio file decoding.
public enum AudioDecoderError: Error, LocalizedError {
    /// The audio file at the given URL cannot be opened.
    case cannotOpenFile(url: URL, underlying: Error)
    /// Failed to create the target audio format.
    case cannotCreateTargetFormat
    /// The audio converter could not be created.
    case converterCreationFailed(sourceSampleRate: Double, sourceChannels: UInt32)
    /// Buffer allocation failed.
    case bufferAllocationFailed(frames: AVAudioFrameCount)
    /// Reading audio data from the file failed.
    case readFailed(underlying: Error)
    /// Audio format conversion failed.
    case conversionFailed(underlying: Error?)
    /// The output buffer contains no channel data.
    case noChannelData

    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let url, let error):
            return "Cannot open audio file at \(url.lastPathComponent): \(error.localizedDescription)"
        case .cannotCreateTargetFormat:
            return "Cannot create 16 kHz mono Float32 target format."
        case .converterCreationFailed(let rate, let channels):
            return "Cannot create converter from \(rate) Hz / \(channels) ch to 16 kHz mono."
        case .bufferAllocationFailed(let frames):
            return "Cannot allocate PCM buffer with \(frames) frames."
        case .readFailed(let error):
            return "Failed to read audio data: \(error.localizedDescription)"
        case .conversionFailed(let error):
            if let error {
                return "Audio conversion failed: \(error.localizedDescription)"
            }
            return "Audio conversion failed."
        case .noChannelData:
            return "Output buffer contains no channel data."
        }
    }
}

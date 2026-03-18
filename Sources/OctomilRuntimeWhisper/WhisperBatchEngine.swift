import Foundation
import Octomil
import whisper

/// Batch speech-to-text engine backed by whisper.cpp.
///
/// Conforms to ``StreamingInferenceEngine`` for the `.audio` modality.
/// Unlike the streaming sherpa-onnx engine, whisper.cpp processes full audio
/// in a single pass and emits per-segment results.
///
/// Accepts `[Float]` PCM samples (16 kHz, mono, normalized to [-1, 1])
/// or `Data` containing raw 16-bit PCM bytes.
final class WhisperBatchEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let modelPath: URL

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let path = modelPath.path

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let samples = try Self.extractSamples(from: input)
                    print("[Whisper] samples count: \(samples.count), first 5: \(Array(samples.prefix(5)))")

                    var params = whisper_context_default_params()
                    #if targetEnvironment(simulator)
                    params.use_gpu = false
                    #else
                    params.flash_attn = true
                    #endif

                    print("[Whisper] Loading model from: \(path)")
                    guard let ctx = whisper_init_from_file_with_params(path, params) else {
                        print("[Whisper] ERROR: Failed to load model at \(path)")
                        throw WhisperError.modelLoadFailed(path)
                    }
                    print("[Whisper] Model loaded successfully")
                    defer { whisper_free(ctx) }

                    // Configure transcription parameters
                    let maxThreads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
                    var fullParams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                    fullParams.print_realtime = false
                    fullParams.print_progress = false
                    fullParams.print_timestamps = false
                    fullParams.print_special = false
                    fullParams.translate = false
                    fullParams.no_context = true
                    fullParams.single_segment = false
                    fullParams.n_threads = maxThreads

                    // Run full transcription
                    let result = samples.withUnsafeBufferPointer { buffer in
                        whisper_full(ctx, fullParams, buffer.baseAddress, Int32(buffer.count))
                    }

                    print("[Whisper] whisper_full returned: \(result)")
                    if result != 0 {
                        throw WhisperError.transcriptionFailed
                    }

                    // Emit one chunk per segment
                    let nSegments = whisper_full_n_segments(ctx)
                    print("[Whisper] nSegments: \(nSegments)")
                    for i in 0..<nSegments {
                        if Task.isCancelled { break }

                        guard let cstr = whisper_full_get_segment_text(ctx, i) else { continue }
                        let text = String(cString: cstr)
                        guard !text.isEmpty else { continue }

                        let chunk = InferenceChunk(
                            index: Int(i),
                            data: Data(text.utf8),
                            modality: .audio,
                            timestamp: Date(),
                            latencyMs: 0
                        )
                        continuation.yield(chunk)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private static func extractSamples(from input: Any) throws -> [Float] {
        if let samples = input as? [Float] {
            return samples
        } else if let data = input as? Data {
            // Strip WAV/RIFF header if present (44 bytes for standard PCM WAV).
            let pcmData: Data
            if data.count > 44,
               data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46 { // "RIFF"
                pcmData = data.subdata(in: 44..<data.count)
            } else {
                pcmData = data
            }

            let count = pcmData.count / 2
            var samples = [Float](repeating: 0, count: count)
            pcmData.withUnsafeBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<count {
                    samples[i] = Float(int16Buffer[i]) / 32768.0
                }
            }
            return samples
        } else {
            throw WhisperError.invalidInput("Expected [Float] or Data, got \(type(of: input))")
        }
    }
}

// MARK: - Errors

enum WhisperError: Error, LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Failed to load whisper model at \(path)"
        case .transcriptionFailed: return "whisper_full() failed"
        case .invalidInput(let msg): return "Invalid audio input: \(msg)"
        }
    }
}

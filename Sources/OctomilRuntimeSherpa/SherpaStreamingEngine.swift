import Foundation
import Octomil
import sherpa_onnx

/// Streaming speech-to-text engine backed by sherpa-onnx.
///
/// Conforms to ``StreamingInferenceEngine`` for the `.audio` modality.
/// Accepts `[Float]` PCM samples (16 kHz, mono, normalized to [-1, 1])
/// or `Data` containing raw PCM bytes.
final class SherpaStreamingEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let modelPath: URL

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let modelDir = modelPath.path

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let samples = try Self.extractSamples(from: input)

                    // Discover model files in the model directory
                    let config = try Self.buildRecognizerConfig(modelDir: modelDir)

                    var configCopy = config
                    guard let recognizer = SherpaOnnxCreateOnlineRecognizer(&configCopy) else {
                        throw SherpaError.recognizerInitFailed
                    }
                    defer { SherpaOnnxDestroyOnlineRecognizer(recognizer) }

                    guard let stream = SherpaOnnxCreateOnlineStream(recognizer) else {
                        throw SherpaError.streamInitFailed
                    }
                    defer { SherpaOnnxDestroyOnlineStream(stream) }

                    // Feed audio in chunks to enable streaming partial results
                    let chunkSize = 3200 // 200ms at 16kHz
                    var offset = 0
                    var chunkIndex = 0
                    var lastText = ""

                    while offset < samples.count {
                        if Task.isCancelled { break }

                        let end = min(offset + chunkSize, samples.count)
                        let chunk = Array(samples[offset..<end])
                        SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, chunk, Int32(chunk.count))
                        offset = end

                        // Decode available frames
                        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
                            SherpaOnnxDecodeOnlineStream(recognizer, stream)
                        }

                        // Get partial result
                        if let resultPtr = SherpaOnnxGetOnlineStreamResult(recognizer, stream) {
                            let text: String
                            if let cstr = resultPtr.pointee.text {
                                text = String(cString: cstr)
                            } else {
                                text = ""
                            }
                            SherpaOnnxDestroyOnlineRecognizerResult(resultPtr)

                            // Only yield when text changes
                            if text != lastText && !text.isEmpty {
                                let delta = String(text.dropFirst(lastText.count))
                                if !delta.isEmpty {
                                    let inferenceChunk = InferenceChunk(
                                        index: chunkIndex,
                                        data: Data(delta.utf8),
                                        modality: .audio,
                                        timestamp: Date(),
                                        latencyMs: 0
                                    )
                                    continuation.yield(inferenceChunk)
                                    chunkIndex += 1
                                }
                                lastText = text
                            }
                        }
                    }

                    // Signal end of input and decode remaining
                    SherpaOnnxOnlineStreamInputFinished(stream)
                    while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
                        SherpaOnnxDecodeOnlineStream(recognizer, stream)
                    }

                    // Final result
                    if let resultPtr = SherpaOnnxGetOnlineStreamResult(recognizer, stream) {
                        let text: String
                        if let cstr = resultPtr.pointee.text {
                            text = String(cString: cstr)
                        } else {
                            text = ""
                        }
                        SherpaOnnxDestroyOnlineRecognizerResult(resultPtr)

                        if text != lastText && !text.isEmpty {
                            let delta = String(text.dropFirst(lastText.count))
                            if !delta.isEmpty {
                                let inferenceChunk = InferenceChunk(
                                    index: chunkIndex,
                                    data: Data(delta.utf8),
                                    modality: .audio,
                                    timestamp: Date(),
                                    latencyMs: 0
                                )
                                continuation.yield(inferenceChunk)
                            }
                        }
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

            // Interpret as 16-bit PCM and convert to Float [-1, 1]
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
            throw SherpaError.invalidInput("Expected [Float] or Data, got \(type(of: input))")
        }
    }

    /// Build recognizer config by discovering model files in the directory.
    private static func buildRecognizerConfig(
        modelDir: String
    ) throws -> SherpaOnnxOnlineRecognizerConfig {
        let fm = FileManager.default

        // Find tokens file
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        guard fm.fileExists(atPath: tokensPath) else {
            throw SherpaError.missingFile("tokens.txt in \(modelDir)")
        }

        // Detect model type by looking for known file patterns
        let contents = (try? fm.contentsOfDirectory(atPath: modelDir)) ?? []
        let onnxFiles = contents.filter { $0.hasSuffix(".onnx") }

        let hasEncoder = onnxFiles.contains { $0.contains("encoder") }
        let hasDecoder = onnxFiles.contains { $0.contains("decoder") }
        let hasJoiner = onnxFiles.contains { $0.contains("joiner") }

        let featConfig = SherpaOnnxFeatureConfig(sample_rate: 16000, feature_dim: 80)

        let nThreads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))

        if hasEncoder && hasDecoder && hasJoiner {
            // Transducer model
            let encoder = onnxFiles.first { $0.contains("encoder") } ?? ""
            let decoder = onnxFiles.first { $0.contains("decoder") } ?? ""
            let joiner = onnxFiles.first { $0.contains("joiner") } ?? ""

            var transducer = SherpaOnnxOnlineTransducerModelConfig(
                encoder: strdup((modelDir as NSString).appendingPathComponent(encoder)),
                decoder: strdup((modelDir as NSString).appendingPathComponent(decoder)),
                joiner: strdup((modelDir as NSString).appendingPathComponent(joiner))
            )

            var modelConfig = sherpaOnnxOnlineModelConfig(
                tokens: tokensPath,
                transducer: transducer,
                numThreads: Int(nThreads)
            )

            return sherpaOnnxOnlineRecognizerConfig(
                featConfig: featConfig,
                modelConfig: modelConfig,
                enableEndpoint: true,
                rule1MinTrailingSilence: 2.4,
                rule2MinTrailingSilence: 1.2,
                rule3MinUtteranceLength: 30
            )
        } else {
            throw SherpaError.unsupportedModelLayout(
                "Could not determine model type from files: \(onnxFiles.joined(separator: ", "))"
            )
        }
    }
}

// MARK: - Errors

enum SherpaError: Error, LocalizedError {
    case recognizerInitFailed
    case streamInitFailed
    case invalidInput(String)
    case missingFile(String)
    case unsupportedModelLayout(String)

    var errorDescription: String? {
        switch self {
        case .recognizerInitFailed: return "Failed to create sherpa-onnx online recognizer"
        case .streamInitFailed: return "Failed to create sherpa-onnx online stream"
        case .invalidInput(let msg): return "Invalid audio input: \(msg)"
        case .missingFile(let msg): return "Missing required file: \(msg)"
        case .unsupportedModelLayout(let msg): return "Unsupported model layout: \(msg)"
        }
    }
}

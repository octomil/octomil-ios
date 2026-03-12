import Foundation

/// CoreML-based audio generation engine for iOS.
///
/// Audio frames are emitted as chunks, each containing a buffer of PCM samples.
public final class AudioEngine: StreamingInferenceEngine, @unchecked Sendable {

    /// Path to the CoreML audio model package.
    private let modelPath: URL

    /// Number of audio frames to generate.
    public var totalFrames: Int

    /// Sample rate in Hz.
    public var sampleRate: Int

    /// Creates an audio generation engine.
    /// - Parameters:
    ///   - modelPath: File URL pointing to the CoreML model package.
    ///   - totalFrames: Number of audio frames to generate (default: 80).
    ///   - sampleRate: Audio sample rate (default: 16000).
    public init(modelPath: URL, totalFrames: Int = 80, sampleRate: Int = 16000) {
        self.modelPath = modelPath
        self.totalFrames = totalFrames
        self.sampleRate = sampleRate
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input _: Any, modality _: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let totalFrames = self.totalFrames

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for frame in 0..<totalFrames {
                        if Task.isCancelled { break }

                        // Placeholder PCM frame (1024 samples x 2 bytes each)
                        let frameData = Data(repeating: 0, count: 2048)
                        let chunk = InferenceChunk(
                            index: frame,
                            data: frameData,
                            modality: .audio,
                            timestamp: Date(),
                            latencyMs: 0
                        )
                        continuation.yield(chunk)

                        try await Task.sleep(nanoseconds: 25_000_000) // 25ms
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

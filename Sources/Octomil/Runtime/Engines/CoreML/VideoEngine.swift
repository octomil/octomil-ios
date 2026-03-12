import Foundation

/// CoreML-based video generation engine for iOS.
///
/// Video frames are emitted as chunks, each containing raw pixel data
/// for a single frame.
public final class VideoEngine: StreamingInferenceEngine, @unchecked Sendable {

    /// Path to the CoreML video model package.
    private let modelPath: URL

    /// Number of frames to generate.
    public var frameCount: Int

    /// Frame width in pixels.
    public var width: Int

    /// Frame height in pixels.
    public var height: Int

    /// Creates a video generation engine.
    /// - Parameters:
    ///   - modelPath: File URL pointing to the CoreML model package.
    ///   - frameCount: Number of frames to generate (default: 30).
    ///   - width: Frame width (default: 256).
    ///   - height: Frame height (default: 256).
    public init(modelPath: URL, frameCount: Int = 30, width: Int = 256, height: Int = 256) {
        self.modelPath = modelPath
        self.frameCount = frameCount
        self.width = width
        self.height = height
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input _: Any, modality _: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let frameCount = self.frameCount

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for frame in 0..<frameCount {
                        if Task.isCancelled { break }

                        // Placeholder frame data (zeroed buffer)
                        let frameData = Data(repeating: 0, count: 1024)
                        let chunk = InferenceChunk(
                            index: frame,
                            data: frameData,
                            modality: .video,
                            timestamp: Date(),
                            latencyMs: 0
                        )
                        continuation.yield(chunk)

                        try await Task.sleep(nanoseconds: 33_000_000) // ~30fps
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

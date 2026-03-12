import Foundation

/// CoreML-based image generation engine for iOS.
///
/// Each denoising step in the diffusion process emits a chunk containing
/// the current image state, allowing callers to display progressive output.
public final class ImageEngine: StreamingInferenceEngine, @unchecked Sendable {

    /// Path to the CoreML diffusion model package.
    private let modelPath: URL

    /// Number of diffusion steps.
    public var steps: Int

    /// Guidance scale for classifier-free guidance.
    public var guidanceScale: Double

    /// Creates an image generation engine.
    /// - Parameters:
    ///   - modelPath: File URL pointing to the CoreML model package.
    ///   - steps: Number of diffusion steps (default: 20).
    ///   - guidanceScale: CFG scale (default: 7.5).
    public init(modelPath: URL, steps: Int = 20, guidanceScale: Double = 7.5) {
        self.modelPath = modelPath
        self.steps = steps
        self.guidanceScale = guidanceScale
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input _: Any, modality _: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let steps = self.steps

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for step in 0..<steps {
                        if Task.isCancelled { break }

                        // Each step produces a partial image (placeholder pixel data).
                        let stepData = Data(repeating: UInt8(step % 256), count: 1024)
                        let chunk = InferenceChunk(
                            index: step,
                            data: stepData,
                            modality: .image,
                            timestamp: Date(),
                            latencyMs: 0
                        )
                        continuation.yield(chunk)

                        // Simulate per-step latency
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
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

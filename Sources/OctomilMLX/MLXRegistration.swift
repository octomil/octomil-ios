import Foundation
import MLXLMCommon
import Octomil

/// Lazy-loading wrapper that defers MLX model loading to the first `generate()` call.
@available(iOS 17.0, macOS 14.0, *)
private final class LazyMLXEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let loader: MLXModelLoader
    private let modelURL: URL
    private let maxTokens: Int
    private let temperature: Float

    init(loader: MLXModelLoader, modelURL: URL, maxTokens: Int = 512, temperature: Float = 0.7) {
        self.loader = loader
        self.modelURL = modelURL
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let loader = self.loader
        let url = self.modelURL
        let maxTokens = self.maxTokens
        let temperature = self.temperature

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await loader.loadModel(from: url)
                    let engine = MLXLLMEngine(
                        modelContainer: container,
                        maxTokens: maxTokens,
                        temperature: temperature
                    )
                    let innerStream = engine.generate(input: input, modality: modality)
                    for try await chunk in innerStream {
                        continuation.yield(chunk)
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

@available(iOS 17.0, macOS 14.0, *)
extension EngineRegistry {

    /// Register the MLX LLM engine for text generation.
    ///
    /// After calling this method, any `resolve(modality: .text, engine: .mlx, ...)`
    /// call will produce an engine that lazily loads the model via the provided
    /// ``MLXModelLoader`` on the first `generate()` invocation.
    ///
    /// - Parameter loader: The ``MLXModelLoader`` used to load MLX model containers.
    public func registerMLX(loader: MLXModelLoader) {
        register(modality: .text, engine: .mlx) { url in
            LazyMLXEngine(loader: loader, modelURL: url)
        }
    }
}

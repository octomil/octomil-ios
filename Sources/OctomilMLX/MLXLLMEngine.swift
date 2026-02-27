import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import Octomil

/// Real MLX-backed LLM inference engine conforming to ``StreamingInferenceEngine``.
///
/// Uses `mlx-swift-lm`'s ``ModelContainer`` for token-by-token generation on Apple Silicon.
/// Requires iOS 17+ / macOS 14+.
@available(iOS 17.0, macOS 14.0, *)
public final class MLXLLMEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let modelContainer: ModelContainer
    public var maxTokens: Int
    public var temperature: Float

    /// Creates an MLX LLM engine.
    /// - Parameters:
    ///   - modelContainer: A loaded MLX model container.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    ///   - temperature: Sampling temperature (default: 0.7).
    public init(modelContainer: ModelContainer, maxTokens: Int = 512, temperature: Float = 0.7) {
        self.modelContainer = modelContainer
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let prompt: String
        if let str = input as? String {
            prompt = str
        } else {
            prompt = String(describing: input)
        }

        let maxTokens = self.maxTokens
        let temperature = self.temperature
        let container = self.modelContainer

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = 0

                    let result = try await container.perform { context in
                        let input = try await context.processor.prepare(input: .init(prompt: prompt))
                        return try MLXLMCommon.generate(
                            input: input,
                            parameters: .init(temperature: temperature, topP: 0.9),
                            context: context
                        ) { tokens in
                            if Task.isCancelled {
                                return .stop
                            }

                            let tokenCount = tokens.count
                            if tokenCount > index {
                                let newText = context.tokenizer.decode(tokens: Array(tokens[index...]))
                                let data = Data(newText.utf8)
                                let chunk = InferenceChunk(
                                    index: index,
                                    data: data,
                                    modality: .text,
                                    timestamp: Date(),
                                    latencyMs: 0
                                )
                                continuation.yield(chunk)
                                index = tokenCount
                            }

                            if tokenCount >= maxTokens {
                                return .stop
                            }

                            return .more
                        }
                    }

                    _ = result
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

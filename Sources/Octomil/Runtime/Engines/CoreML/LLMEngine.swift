import Foundation

/// MLX-based text generation engine for iOS.
///
/// Each generated token is emitted as an ``InferenceChunk`` containing
/// UTF-8 encoded token text. Timing is handled by the
/// ``InstrumentedStreamWrapper``.
public final class LLMEngine: StreamingInferenceEngine, @unchecked Sendable {

    /// Path to the MLX model directory.
    private let modelPath: URL

    /// Maximum number of tokens to generate.
    public var maxTokens: Int

    /// Temperature for sampling.
    public var temperature: Double

    /// Creates an LLM engine.
    /// - Parameters:
    ///   - modelPath: File URL pointing to the MLX model directory.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    ///   - temperature: Sampling temperature (default: 0.7).
    public init(modelPath: URL, maxTokens: Int = 512, temperature: Double = 0.7) {
        self.modelPath = modelPath
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input: Any, modality _: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let prompt: String
        if let str = input as? String {
            prompt = str
        } else {
            prompt = String(describing: input)
        }

        let modelPath = self.modelPath
        let maxTokens = self.maxTokens
        let temperature = self.temperature

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Attempt to use mlx-swift for token-by-token generation.
                    // If mlx-swift is not available, fall back to a simulated stream.
                    let tokens = try await Self.generateTokens(
                        prompt: prompt,
                        modelPath: modelPath,
                        maxTokens: maxTokens,
                        temperature: temperature
                    )

                    for (index, token) in tokens.enumerated() {
                        if Task.isCancelled { break }

                        let data = Data(token.utf8)
                        let chunk = InferenceChunk(
                            index: index,
                            data: data,
                            modality: .text,
                            timestamp: Date(),
                            latencyMs: 0 // filled by InstrumentedStreamWrapper
                        )
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

    // MARK: - Private

    /// Generate tokens using mlx-swift (or a placeholder implementation).
    private static func generateTokens(
        prompt: String,
        modelPath _: URL,
        maxTokens: Int,
        temperature _: Double
    ) async throws -> [String] {
        // In production this would use `import MLX` and `import MLXLLM`.
        // For now, return a placeholder stream demonstrating the interface.
        // Replace this body once mlx-swift is linked.
        var tokens: [String] = []
        let words = prompt.split(separator: " ")
        let response = "This is a generated response for: \(words.prefix(3).joined(separator: " "))..."
        for word in response.split(separator: " ").prefix(maxTokens) {
            tokens.append(String(word) + " ")
            // Simulate per-token latency
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        return tokens
    }
}

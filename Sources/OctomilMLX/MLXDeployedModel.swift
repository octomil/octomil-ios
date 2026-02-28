import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil

/// MLX equivalent of ``DeployedModel`` for LLM inference.
///
/// Wraps a ``ModelContainer`` and provides instrumented streaming generation
/// via the same ``InstrumentedStreamWrapper`` used by the base SDK.
@available(iOS 17.0, macOS 14.0, *)
public final class MLXDeployedModel: @unchecked Sendable {

    /// Human-readable model name.
    public let name: String

    /// The underlying MLX model container.
    public let modelContainer: ModelContainer

    /// Maximum tokens to generate per request.
    public var maxTokens: Int

    /// Sampling temperature.
    public var temperature: Float

    public init(
        name: String,
        modelContainer: ModelContainer,
        maxTokens: Int = 512,
        temperature: Float = 0.7
    ) {
        self.name = name
        self.modelContainer = modelContainer
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    /// Generate text with instrumented timing metrics.
    /// - Parameter prompt: The text prompt.
    /// - Returns: Tuple of (instrumented stream, result closure).
    public func predictStream(
        prompt: String
    ) -> (
        stream: AsyncThrowingStream<InferenceChunk, Error>,
        result: @Sendable () -> StreamingInferenceResult?
    ) {
        let engine = MLXLLMEngine(
            modelContainer: modelContainer,
            maxTokens: maxTokens,
            temperature: temperature
        )
        let wrapper = InstrumentedStreamWrapper(modality: .text)
        return wrapper.wrap(engine, input: prompt)
    }

    /// Generate text with a specific modality (for protocol flexibility).
    public func predictStream(
        input: Any,
        modality: Modality
    ) -> (
        stream: AsyncThrowingStream<InferenceChunk, Error>,
        result: @Sendable () -> StreamingInferenceResult?
    ) {
        let engine = MLXLLMEngine(
            modelContainer: modelContainer,
            maxTokens: maxTokens,
            temperature: temperature
        )
        let wrapper = InstrumentedStreamWrapper(modality: modality)
        return wrapper.wrap(engine, input: input)
    }
}

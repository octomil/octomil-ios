import Foundation
import CoreML

/// A model deployed to a specific inference engine.
public final class DeployedModel: @unchecked Sendable {
    /// Human-readable model name (derived from filename).
    public let name: String

    /// The inference engine used.
    public let engine: Engine

    /// The underlying Octomil model.
    public let model: OctomilModel

    /// Warmup benchmark results, populated when deployed with `benchmark: true`.
    public internal(set) var warmupResult: WarmupResult?

    /// Active compute delegate after benchmarking (e.g. "neural_engine", "cpu").
    public var activeDelegate: String { warmupResult?.activeDelegate ?? "unknown" }

    internal init(name: String, engine: Engine, model: OctomilModel, warmupResult: WarmupResult? = nil) {
        self.name = name
        self.engine = engine
        self.model = model
        self.warmupResult = warmupResult
    }

    /// Run prediction with an MLFeatureProvider input.
    public func predict(input: MLFeatureProvider) throws -> MLFeatureProvider {
        return try model.predict(input: input)
    }

    /// Run prediction with a dictionary input.
    public func predict(inputs: [String: Any]) throws -> MLFeatureProvider {
        return try model.predict(inputs: inputs)
    }

    /// Run batch prediction.
    public func predict(batch inputBatch: MLBatchProvider) throws -> MLBatchProvider {
        return try model.predict(batch: inputBatch)
    }

    /// Run streaming generative inference.
    public func predictStream(
        input: Any,
        modality: Modality,
        engine streamingEngine: StreamingInferenceEngine? = nil
    ) -> (
        stream: AsyncThrowingStream<InferenceChunk, Error>,
        result: @Sendable () -> StreamingInferenceResult?
    ) {
        return model.predictStream(input: input, modality: modality, engine: streamingEngine)
    }
}

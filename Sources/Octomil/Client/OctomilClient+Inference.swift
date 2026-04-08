import Foundation
import CoreML

// MARK: - Inference

extension OctomilClient {

    // MARK: - Streaming Inference

    /// Streams generative inference and auto-reports metrics to the server.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - input: Modality-specific input.
    ///   - modality: The output modality.
    ///   - engine: Optional custom engine. Defaults to a modality-appropriate engine.
    /// - Returns: An ``AsyncThrowingStream`` of ``InferenceChunk``.
    public func predictStream(
        model: OctomilModel,
        input: Any,
        modality: Modality,
        engine: StreamingInferenceEngine? = nil
    ) -> AsyncThrowingStream<InferenceChunk, Error> {
        let (stream, getResult) = model.predictStream(input: input, modality: modality, engine: engine)
        let apiClient = self.apiClient
        let deviceId = self.deviceId
        let orgId = self.orgId
        let sessionId = UUID().uuidString

        // Report generation_started via v2 OTLP
        if let deviceId = deviceId {
            Task {
                let resource = TelemetryResource(deviceId: deviceId, orgId: orgId)
                let event = TelemetryEvent(
                    name: "inference.generation_started",
                    attributes: [
                        "model.id": .string(model.id),
                        "model.version": .string(model.version),
                        "inference.modality": .string(modality.rawValue),
                        "inference.session_id": .string(sessionId),
                        "model.format": .string(model.metadata.format),
                    ]
                )
                let envelope = TelemetryEnvelope(resource: resource, events: [event])
                try? await apiClient.reportTelemetryEvents(envelope)
            }
        }

        // Wrap the stream to report completion via v2 OTLP
        return AsyncThrowingStream<InferenceChunk, Error> { continuation in
            let task = Task {
                var failed = false
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                } catch {
                    failed = true
                    continuation.finish(throwing: error)
                }

                if !failed {
                    continuation.finish()
                }

                // Report completion event via v2 OTLP
                if let deviceId = deviceId, let result = getResult() {
                    let eventName = failed ? "inference.generation_failed" : "inference.generation_completed"
                    var attrs: [String: TelemetryValue] = [
                        "model.id": .string(model.id),
                        "model.version": .string(model.version),
                        "inference.modality": .string(modality.rawValue),
                        "inference.session_id": .string(sessionId),
                        "inference.ttft_ms": .double(result.ttfcMs),
                        "inference.duration_ms": .double(result.totalDurationMs),
                        "inference.total_chunks": .int(result.totalChunks),
                        "inference.throughput": .double(result.throughput),
                        "model.format": .string(model.metadata.format),
                    ]
                    if failed {
                        attrs["inference.success"] = .bool(false)
                    }
                    let resource = TelemetryResource(deviceId: deviceId, orgId: orgId)
                    let event = TelemetryEvent(name: eventName, attributes: attrs)
                    let envelope = TelemetryEnvelope(resource: resource, events: [event])
                    try? await apiClient.reportTelemetryEvents(envelope)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Direct Inference

    /// Runs inference on a model with raw input data.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - input: Input feature provider.
    /// - Returns: Model prediction output.
    /// - Throws: Error if inference fails.
    public func runInference(
        model: OctomilModel,
        input: MLFeatureProvider
    ) throws -> MLFeatureProvider {
        return try model.predict(input: input)
    }

    /// Classifies input and returns top-K predictions sorted by confidence.
    ///
    /// - Parameters:
    ///   - model: The model to classify with.
    ///   - input: Input feature provider.
    ///   - topK: Number of top predictions to return (default: 5).
    /// - Returns: Array of (feature name, confidence) pairs.
    /// - Throws: Error if inference fails.
    public func classify(
        model: OctomilModel,
        input: MLFeatureProvider,
        topK: Int = 5
    ) throws -> [(String, Double)] {
        let output = try model.predict(input: input)
        var results: [(String, Double)] = []

        for name in output.featureNames {
            if let value = output.featureValue(for: name) {
                switch value.type {
                case .double:
                    results.append((name, value.doubleValue))
                case .int64:
                    results.append((name, Double(value.int64Value)))
                case .multiArray:
                    if let array = value.multiArrayValue {
                        for i in 0..<array.count {
                            results.append(("\(name)_\(i)", array[i].doubleValue))
                        }
                    }
                case .dictionary:
                    if let dict = value.dictionaryValue as? [String: NSNumber] {
                        for (key, val) in dict {
                            results.append((key, val.doubleValue))
                        }
                    }
                default:
                    break
                }
            }
        }

        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(topK))
    }

    /// Runs batch inference on a model.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - inputs: Batch of input feature providers.
    /// - Returns: Batch of predictions.
    /// - Throws: Error if inference fails.
    public func runBatchInference(
        model: OctomilModel,
        inputs: MLBatchProvider
    ) throws -> MLBatchProvider {
        return try model.predict(batch: inputs)
    }

    /// Runs inference with a preprocessing step.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - currentInput: Raw input data.
    ///   - preprocess: Closure that transforms raw input into model-compatible features.
    /// - Returns: Model prediction output.
    /// - Throws: Error if preprocessing or inference fails.
    public func runPipelinedInference(
        model: OctomilModel,
        currentInput: Any,
        preprocess: (Any) throws -> MLFeatureProvider
    ) throws -> MLFeatureProvider {
        let features = try preprocess(currentInput)
        return try model.predict(input: features)
    }
}

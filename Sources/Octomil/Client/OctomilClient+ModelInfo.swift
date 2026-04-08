import Foundation
import CoreML

// MARK: - Model Contract, Info & Warmup

extension OctomilClient {

    /// Returns the model's input/output contract for validation.
    ///
    /// Use this at setup time to validate that your data pipeline produces
    /// the correct shapes and types before calling inference or training.
    ///
    /// - Parameter model: The model to inspect.
    /// - Returns: A ``ModelContract`` describing the model, or nil if tensor info is unavailable.
    public func getModelContract(for model: OctomilModel) -> ModelContract? {
        guard let tensorInfo = getTensorInfo(for: model) else {
            return nil
        }
        return ModelContract(
            modelId: model.id,
            version: model.version,
            inputShape: tensorInfo.inputShape,
            outputShape: tensorInfo.outputShape,
            inputType: tensorInfo.inputType,
            outputType: tensorInfo.outputType,
            hasTrainingSignature: model.supportsTraining,
            signatureKeys: model.supportsTraining ? ["train", "infer"] : ["infer"]
        )
    }

    /// Returns summary information about a loaded model.
    ///
    /// - Parameter model: The model to inspect.
    /// - Returns: A ``ModelInfo`` describing the model.
    public func getModelInfo(for model: OctomilModel) -> ModelInfo {
        let tensorInfo = getTensorInfo(for: model)
        return ModelInfo(
            modelId: model.id,
            version: model.version,
            format: model.metadata.format,
            sizeBytes: Int64(model.metadata.fileSize),
            inputShape: tensorInfo?.inputShape ?? [],
            outputShape: tensorInfo?.outputShape ?? [],
            usingNeuralEngine: hasNeuralEngine()
        )
    }

    /// Returns tensor shape/type information for a loaded model.
    ///
    /// - Parameter model: The model to inspect.
    /// - Returns: A ``TensorInfo`` with input/output shapes and types, or nil if unavailable.
    public func getTensorInfo(for model: OctomilModel) -> TensorInfo? {
        let inputDescs = model.mlModel.modelDescription.inputDescriptionsByName
        let outputDescs = model.mlModel.modelDescription.outputDescriptionsByName

        guard let firstInput = inputDescs.values.first,
              let firstOutput = outputDescs.values.first else {
            return nil
        }

        let inputShape = extractShape(from: firstInput)
        let outputShape = extractShape(from: firstOutput)
        let inputType = describeFeatureType(firstInput.type)
        let outputType = describeFeatureType(firstOutput.type)

        return TensorInfo(
            inputShape: inputShape,
            outputShape: outputShape,
            inputType: inputType,
            outputType: outputType
        )
    }

    // MARK: - Warmup

    /// Runs warmup inference to absorb cold-start costs before real inference.
    ///
    /// Delegates to ``OctomilModel/warmup()`` for the actual warmup passes,
    /// then reports timing telemetry to the server.
    ///
    /// - Parameter model: The model to warm up.
    /// - Returns: A ``WarmupResult`` with timing information, or nil if warmup fails.
    public func warmup(model: OctomilModel) async -> WarmupResult? {
        guard let result = await model.warmup() else {
            return nil
        }

        // Report warmup event
        if let deviceId = self.deviceId {
            Task {
                try? await apiClient.trackMetric(
                    experimentId: model.id,
                    event: TrackingEvent(
                        name: "MODEL_WARMUP_COMPLETED",
                        properties: [
                            "cold_inference_ms": String(format: "%.2f", result.coldInferenceMs),
                            "warm_inference_ms": String(format: "%.2f", result.warmInferenceMs),
                            "using_neural_engine": String(result.usingNeuralEngine),
                            "active_delegate": result.activeDelegate,
                            "delegate_disabled": String(result.delegateDisabled),
                            "disabled_delegates": result.disabledDelegates.joined(separator: ",")
                        ]
                    )
                )
            }
        }

        if configuration.enableLogging {
            let coldStr = String(format: "%.1f", result.coldInferenceMs)
            let warmStr = String(format: "%.1f", result.warmInferenceMs)
            logger.info("Warmup complete: cold=\(coldStr)ms, warm=\(warmStr)ms, delegate=\(result.activeDelegate)")
        }

        return result
    }
}

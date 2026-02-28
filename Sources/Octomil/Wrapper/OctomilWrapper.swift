import CoreML
import Foundation
import os.log

/// Namespace for the Octomil drop-in CoreML wrapper.
///
/// Use ``wrap(_:modelId:config:)`` to add Octomil telemetry, validation,
/// and OTA updates to any existing ``MLModel`` with a single line change:
///
/// ```swift
/// // Before
/// let model = try MLModel(contentsOf: modelURL)
///
/// // After
/// let model = try Octomil.wrap(MLModel(contentsOf: modelURL), modelId: "classifier")
///
/// // Call sites use the cross-SDK predict() API
/// let result = try model.predict(input: input)
/// ```
public enum Octomil {

    private static let logger = Logger(subsystem: "ai.octomil.sdk", category: "Octomil")

    /// Wraps an existing CoreML model with Octomil telemetry, input
    /// validation, and OTA update support.
    ///
    /// The returned ``OctomilWrappedModel`` mirrors every ``MLModel``
    /// prediction method so existing call sites require zero changes.
    ///
    /// - Parameters:
    ///   - model: A compiled ``MLModel`` to wrap.
    ///   - modelId: The model identifier registered on the Octomil server.
    ///   - config: Configuration controlling validation, telemetry, and OTA
    ///     behaviour.  Defaults to ``OctomilWrapperConfig/default``.
    /// - Returns: A wrapped model ready for prediction.
    /// - Throws: Never under normal circumstances.  Reserved for future
    ///   config validation errors.
    public static func wrap(
        _ model: MLModel,
        modelId: String,
        config: OctomilWrapperConfig = .default
    ) throws -> OctomilWrappedModel {
        let telemetry = TelemetryQueue(
            modelId: modelId,
            serverURL: config.serverURL,
            apiKey: config.apiKey,
            batchSize: config.telemetryBatchSize,
            flushInterval: config.telemetryFlushInterval
        )

        // Build a contract from the CoreML model description so validation
        // works out of the box even without a server-side contract.
        let inputNames = Set(model.modelDescription.inputDescriptionsByName.keys)
        let outputNames = Set(model.modelDescription.outputDescriptionsByName.keys)
        let localContract = WrappedModelContract(
            inputFeatureNames: inputNames,
            outputFeatureNames: outputNames
        )

        let wrapped = OctomilWrappedModel(
            model: model,
            modelId: modelId,
            config: config,
            telemetry: telemetry,
            serverContract: localContract
        )

        logger.info("Wrapped model \(modelId) with \(inputNames.count) inputs, \(outputNames.count) outputs")

        // Kick off non-blocking OTA check if enabled
        if config.otaUpdatesEnabled {
            wrapped.checkForUpdates()
        }

        return wrapped
    }
}

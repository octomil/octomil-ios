import Foundation
import CoreML

/// Unified model deployment API.
///
/// Loads a model from a local URL, auto-detects the engine, and returns
/// a `DeployedModel` ready for inference. By default runs a warmup benchmark
/// comparing Neural Engine vs CPU to select the best delegate.
public enum Deploy {

    /// Deploy a model from a local file URL.
    ///
    /// - Parameters:
    ///   - url: Path to the model file (`.mlmodelc`, `.mlmodel`, or `.mlpackage`).
    ///   - engine: Inference engine to use. Defaults to `.auto` (CoreML on iOS).
    ///   - name: Human-readable name. Defaults to the filename without extension.
    ///   - benchmark: When `true` (default), runs warmup benchmarks comparing
    ///     Neural Engine vs CPU and selects the fastest delegate. Results are
    ///     stored in ``DeployedModel/warmupResult``.
    /// - Returns: A `DeployedModel` ready for inference.
    /// - Throws: If the model cannot be loaded.
    public static func model(
        at url: URL,
        engine: Engine = .auto,
        name: String? = nil,
        benchmark: Bool = true
    ) throws -> DeployedModel {
        let resolvedName = name ?? url.deletingPathExtension().lastPathComponent
        let resolvedEngine = resolveEngine(engine: engine)

        let mlModel: MLModel
        let compiledURL: URL

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mlmodelc":
            mlModel = try MLModel(contentsOf: url)
            compiledURL = url
        case "mlmodel", "mlpackage":
            let compiled = try MLModel.compileModel(at: url)
            mlModel = try MLModel(contentsOf: compiled)
            compiledURL = compiled
        default:
            throw DeployError.unsupportedFormat(ext)
        }

        let metadata = ModelMetadata(
            modelId: resolvedName,
            version: "local",
            checksum: "",
            fileSize: 0,
            createdAt: Date(),
            format: resolvedEngine.rawValue,
            supportsTraining: mlModel.modelDescription.isUpdatable,
            description: "Locally deployed model",
            inputSchema: nil,
            outputSchema: nil
        )

        let octomilModel = OctomilModel(
            id: resolvedName,
            version: "local",
            mlModel: mlModel,
            metadata: metadata,
            compiledModelURL: compiledURL
        )

        let deployed = DeployedModel(name: resolvedName, engine: resolvedEngine, model: octomilModel)

        if benchmark {
            deployed.warmupResult = try runBenchmark(model: octomilModel, url: compiledURL)
        }

        TelemetryQueue.shared?.reportFunnelEvent(
            stage: "first_inference",
            success: true,
            modelId: resolvedName
        )

        return deployed
    }

    private static func runBenchmark(model: OctomilModel, url: URL) throws -> WarmupResult {
        let dummyInput = try makeDummyInput(for: model.mlModel)

        // Cold inference
        let coldStart = CFAbsoluteTimeGetCurrent()
        _ = try? model.mlModel.prediction(from: dummyInput)
        let coldMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000

        // Warm inference (default compute units — typically Neural Engine)
        let warmStart = CFAbsoluteTimeGetCurrent()
        _ = try? model.mlModel.prediction(from: dummyInput)
        let warmMs = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000

        // CPU-only baseline
        var cpuMs: Double? = nil
        var usingNE = true
        var activeDelegate = "neural_engine"
        var disabled: [String] = []

        let cpuConfig = MLModelConfiguration()
        cpuConfig.computeUnits = .cpuOnly
        if let cpuModel = try? MLModel(contentsOf: url, configuration: cpuConfig) {
            _ = try? cpuModel.prediction(from: dummyInput)
            let cpuStart = CFAbsoluteTimeGetCurrent()
            _ = try? cpuModel.prediction(from: dummyInput)
            let measured = (CFAbsoluteTimeGetCurrent() - cpuStart) * 1000
            cpuMs = measured

            if measured < warmMs {
                usingNE = false
                activeDelegate = "cpu"
                disabled = ["neural_engine"]
            }
        }

        return WarmupResult(
            coldInferenceMs: coldMs,
            warmInferenceMs: warmMs,
            cpuInferenceMs: cpuMs,
            usingNeuralEngine: usingNE,
            activeDelegate: activeDelegate,
            disabledDelegates: disabled
        )
    }

    private static func makeDummyInput(for mlModel: MLModel) throws -> MLFeatureProvider {
        let desc = mlModel.modelDescription
        let dict = NSMutableDictionary()

        for (name, feature) in desc.inputDescriptionsByName {
            if let constraint = feature.multiArrayConstraint {
                let shape = constraint.shape
                let dataType = constraint.dataType
                let array = try MLMultiArray(shape: shape, dataType: dataType)
                dict[name] = array
            } else if let imageConstraint = feature.imageConstraint {
                let width = imageConstraint.pixelsWide
                let height = imageConstraint.pixelsHigh
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
                if let pb = pixelBuffer {
                    dict[name] = pb
                }
            }
        }

        return try MLDictionaryFeatureProvider(dictionary: dict as! [String: Any])
    }

    private static func resolveEngine(engine: Engine) -> Engine {
        switch engine {
        case .auto:
            return .coreml
        case .coreml:
            return .coreml
        }
    }
}

// MARK: - Adaptive Deployment

extension Deploy {

    /// Deploy a model with runtime adaptation.
    ///
    /// The returned ``AdaptiveDeployedModel`` monitors device state (battery,
    /// thermal pressure, memory, low-power mode) and automatically switches
    /// compute units when conditions change. Uses the ``AdaptiveModelLoader``
    /// fallback chain to load the model initially.
    ///
    /// - Parameters:
    ///   - url: Path to the compiled model file (`.mlmodelc`).
    ///   - stateMonitor: Optional pre-configured state monitor. A default monitor
    ///     is created if nil.
    ///   - configuration: SDK configuration.
    /// - Returns: An ``AdaptiveDeployedModel`` that adapts at runtime.
    /// - Throws: If the model cannot be loaded with any compute unit configuration.
    public static func adaptiveModel(
        from url: URL,
        stateMonitor: DeviceStateMonitor? = nil,
        configuration: OctomilConfiguration = .standard
    ) async throws -> AdaptiveDeployedModel {
        let monitor = stateMonitor ?? DeviceStateMonitor()
        let loader = AdaptiveModelLoader()

        // Get initial device state to pick the best starting compute units
        await monitor.startMonitoring()
        let initialState = await monitor.currentState
        let recommendation = RuntimeAdapter.recommend(for: initialState)

        // Load model with fallback chain starting from recommended compute units
        let (mlModel, actualUnits) = try await loader.load(
            from: url,
            preferredComputeUnits: recommendation.computeUnits
        )

        let adaptive = AdaptiveDeployedModel(
            model: mlModel,
            modelURL: url,
            computeUnits: actualUnits,
            stateMonitor: monitor,
            loader: loader
        )

        // Start the adaptation loop
        await adaptive.startAdaptation()

        return adaptive
    }
}

/// Errors from the deploy API.
public enum DeployError: Error, LocalizedError {
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported model format: .\(ext). Supported formats: .mlmodelc, .mlmodel, .mlpackage"
        }
    }
}

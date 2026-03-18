import Foundation
import CoreML
import os.log

/// Unified model deployment API.
///
/// Loads a model from a local URL, auto-detects the engine, and returns
/// a `DeployedModel` ready for inference. By default runs a warmup benchmark
/// comparing Neural Engine vs CPU to select the best delegate.
///
/// When a `pairingCode` and `apiClient` are provided, real benchmark results
/// are submitted to the server after warmup completes. This replaces the
/// previous approach of submitting zeroed-out benchmarks during pairing.
public enum Deploy {

    private static let logger = Logger(subsystem: "ai.octomil.sdk", category: "Deploy")

    /// Deploy a model from a local file URL.
    ///
    /// - Parameters:
    ///   - url: Path to the model file (`.mlmodelc`, `.mlmodel`, or `.mlpackage`).
    ///   - engine: Inference engine to use. Defaults to `.auto` (CoreML on iOS).
    ///   - name: Human-readable name. Defaults to the filename without extension.
    ///   - benchmark: When `true` (default), runs warmup benchmarks comparing
    ///     Neural Engine vs CPU and selects the fastest delegate. Results are
    ///     stored in ``DeployedModel/warmupResult``.
    ///   - pairingCode: Optional pairing code. When provided along with `apiClient`,
    ///     submits real benchmark results to the server after warmup. Submission
    ///     failures are logged but do not cause the method to throw.
    ///   - apiClient: Optional API client for submitting benchmark results.
    ///     Required together with `pairingCode` for server submission.
    /// - Returns: A `DeployedModel` ready for inference.
    /// - Throws: If the model cannot be loaded.
    public static func model(
        at url: URL,
        engine: Engine = .auto,
        name: String? = nil,
        benchmark: Bool = true,
        pairingCode: String? = nil,
        apiClient: APIClient? = nil
    ) async throws -> DeployedModel {
        let resolvedName = name ?? url.deletingPathExtension().lastPathComponent
        let resolvedEngine = resolveEngine(engine: engine)

        // Record deploy started telemetry
        TelemetryQueue.shared?.reportDeployStarted(modelId: resolvedName, version: "local")
        let deployStart = CFAbsoluteTimeGetCurrent()

        if resolvedEngine == .mlx {
            throw DeployError.unsupportedFormat(
                "mlx — add the OctomilMLX package product and use Deploy.mlxModel(at:) instead"
            )
        }

        let mlModel: MLModel
        let compiledURL: URL

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mlmodelc":
            mlModel = try MLModel(contentsOf: url)
            compiledURL = url
        case "mlmodel", "mlpackage":
            let compiled = try await MLModel.compileModel(at: url)
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
            deployed.warmupResult = try await runBenchmark(model: octomilModel, url: compiledURL)
        }

        // Record deploy completed telemetry
        let deployDurationMs = (CFAbsoluteTimeGetCurrent() - deployStart) * 1000
        TelemetryQueue.shared?.reportDeployCompleted(
            modelId: resolvedName,
            version: "local",
            durationMs: deployDurationMs
        )

        TelemetryQueue.shared?.reportFunnelEvent(
            stage: "first_inference",
            success: true,
            modelId: resolvedName
        )

        // Submit real benchmark results to the server if pairing context is provided
        if let code = pairingCode, let client = apiClient, let warmup = deployed.warmupResult {
            await submitBenchmark(
                warmup: warmup,
                modelName: resolvedName,
                modelLoadTimeMs: deployDurationMs,
                activeDelegate: warmup.activeDelegate,
                code: code,
                apiClient: client
            )
        }

        return deployed
    }

    private static func runBenchmark(model: OctomilModel, url: URL) async throws -> WarmupResult {
        let dummyInput = try makeDummyInput(for: model.mlModel)

        // Cold inference
        let coldStart = CFAbsoluteTimeGetCurrent()
        _ = try? await model.mlModel.prediction(from: dummyInput)
        let coldMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000

        // Warm inference (default compute units — typically Neural Engine)
        let warmStart = CFAbsoluteTimeGetCurrent()
        _ = try? await model.mlModel.prediction(from: dummyInput)
        let warmMs = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000

        // CPU-only baseline
        var cpuMs: Double? = nil
        var usingNE = true
        var activeDelegate = "neural_engine"
        var disabled: [String] = []

        let cpuConfig = MLModelConfiguration()
        cpuConfig.computeUnits = .cpuOnly
        if let cpuModel = try? MLModel(contentsOf: url, configuration: cpuConfig) {
            _ = try? await cpuModel.prediction(from: dummyInput)
            let cpuStart = CFAbsoluteTimeGetCurrent()
            _ = try? await cpuModel.prediction(from: dummyInput)
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

    // MARK: - Benchmark Submission

    /// Converts warmup results to a BenchmarkReport and submits to the server.
    /// Non-fatal: logs a warning on failure but does not propagate errors.
    private static func submitBenchmark(
        warmup: WarmupResult,
        modelName: String,
        modelLoadTimeMs: Double,
        activeDelegate: String,
        code: String,
        apiClient: APIClient
    ) async {
        let caps = PairingDeviceCapabilities.current()
        let tokensPerSecond = warmup.warmInferenceMs > 0 ? (1000.0 / warmup.warmInferenceMs) : 0

        let report = BenchmarkReport(
            modelName: modelName,
            deviceName: caps.deviceName,
            chipFamily: caps.chipFamily,
            ramGB: caps.ramGB,
            osVersion: caps.osVersion,
            ttftMs: warmup.coldInferenceMs,
            tpotMs: warmup.warmInferenceMs,
            tokensPerSecond: tokensPerSecond,
            p50LatencyMs: warmup.warmInferenceMs,
            p95LatencyMs: warmup.warmInferenceMs,
            p99LatencyMs: warmup.coldInferenceMs,
            memoryPeakBytes: 0,
            inferenceCount: warmup.cpuInferenceMs != nil ? 4 : 2,
            modelLoadTimeMs: modelLoadTimeMs,
            coldInferenceMs: warmup.coldInferenceMs,
            warmInferenceMs: warmup.warmInferenceMs,
            activeDelegate: activeDelegate,
            disabledDelegates: warmup.disabledDelegates
        )

        do {
            try await apiClient.submitPairingBenchmark(code: code, report: report)
            logger.info("Benchmark submitted for pairing code: \(code)")
        } catch {
            logger.warning("Failed to submit benchmark for pairing code \(code): \(error.localizedDescription)")
        }
    }

    // MARK: - Engine Resolution

    private static func resolveEngine(engine: Engine, url: URL? = nil) -> Engine {
        if engine != .auto { return engine }
        if let url = url, let inferred = EngineRegistry.engineFromURL(url) {
            return inferred
        }
        return .coreml
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

import Foundation
import CoreML
import os.log

/// Unified model deployment API.
///
/// Loads a model from a local URL, auto-detects the engine, and returns
/// a `DeployedModel` ready for inference. By default runs a warmup benchmark
/// comparing Neural Engine vs CPU to select the best delegate.
///
/// When a `pairingCode` is provided and `submitBenchmark` is `true` (the default),
/// benchmark results are submitted to the server via a lightweight `URLSession`
/// POST -- no `APIClient` required. The endpoint is unauthenticated.
public enum Deploy {

    private static let logger = Logger(subsystem: "ai.octomil.sdk", category: "Deploy")

    /// Default server URL used when none is supplied.
    private static let defaultServerURL = URL(string: "https://api.octomil.com")!

    /// Deploy a model from a local file URL.
    ///
    /// - Parameters:
    ///   - url: Path to the model file (`.mlmodelc`, `.mlmodel`, or `.mlpackage`).
    ///   - engine: Inference engine to use. Defaults to `.auto` (CoreML on iOS).
    ///   - name: Human-readable name. Defaults to the filename without extension.
    ///   - benchmark: When `true` (default), runs warmup benchmarks comparing
    ///     Neural Engine vs CPU and selects the fastest delegate. Results are
    ///     stored in ``DeployedModel/warmupResult``.
    ///   - pairingCode: Optional pairing code. When provided, benchmark results
    ///     are submitted to the server after warmup (unless `submitBenchmark` is
    ///     set to `false`). Submission failures are logged but never thrown.
    ///   - submitBenchmark: When `true` (default) and a `pairingCode` is present,
    ///     submits warmup results to the server. Set to `false` to opt out.
    ///   - serverURL: Base URL for benchmark submission. Defaults to
    ///     `https://api.octomil.com`.
    /// - Returns: A `DeployedModel` ready for inference.
    /// - Throws: If the model cannot be loaded.
    public static func model(
        at url: URL,
        engine: Engine = .auto,
        name: String? = nil,
        benchmark: Bool = true,
        pairingCode: String? = nil,
        submitBenchmark: Bool = true,
        serverURL: URL? = nil
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

        // Submit benchmark results to the server (opt-out: on by default)
        if submitBenchmark, let code = pairingCode, let warmup = deployed.warmupResult {
            await Self.submitBenchmarkReport(
                warmup: warmup,
                modelName: resolvedName,
                modelLoadTimeMs: deployDurationMs,
                activeDelegate: warmup.activeDelegate,
                code: code,
                serverURL: serverURL ?? defaultServerURL
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

    /// Converts warmup results to a BenchmarkReport and POSTs it directly
    /// via `URLSession`. No `APIClient` dependency -- the endpoint is
    /// unauthenticated. Non-fatal: logs a warning on failure but does not
    /// propagate errors.
    private static func submitBenchmarkReport(
        warmup: WarmupResult,
        modelName: String,
        modelLoadTimeMs: Double,
        activeDelegate: String,
        code: String,
        serverURL: URL
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
            let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)/benchmark")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

            request.httpBody = try JSONEncoder().encode(report)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                logger.warning("Benchmark submission returned HTTP \(httpResponse.statusCode) for pairing code: \(code)")
            } else {
                logger.info("Benchmark submitted for pairing code: \(code)")
            }
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

// MARK: - CoreML Runtime Evidence

extension InstalledRuntime {

    /// Create runtime evidence for a locally-deployed CoreML model.
    ///
    /// Call this only when a concrete CoreML artifact (.mlmodelc, .mlmodel,
    /// .mlpackage) exists on disk. Framework availability alone is not
    /// sufficient evidence.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "my-classifier", "whisper-tiny").
    ///   - capability: The capability this model provides (e.g. "text", "classification",
    ///     "audio_transcription"). Should match the manifest capability when available.
    ///   - artifactDigest: SHA-256 hex digest of the model file, if known.
    /// - Returns: An ``InstalledRuntime`` with model evidence metadata.
    public static func coreMLEvidence(
        model: String,
        capability: String,
        artifactDigest: String? = nil
    ) -> InstalledRuntime {
        modelCapable(
            engine: "coreml",
            model: model,
            capabilities: [capability],
            accelerator: "ane",
            artifactDigest: artifactDigest,
            artifactFormat: "coreml"
        )
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

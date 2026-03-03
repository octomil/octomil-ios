import Foundation
import CoreML
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Manages the QR code pairing flow for deploying models to this device.
///
/// The pairing flow is:
/// 1. User scans a QR code on the Octomil dashboard
/// 2. Device connects to the pairing session with its capabilities
/// 3. Server prepares an optimized model variant for this device
/// 4. Device downloads the model, runs benchmarks, and reports results
///
/// # Example Usage
///
/// ```swift
/// let manager = PairingManager(serverURL: URL(string: "https://api.octomil.com")!)
/// let report = try await manager.pair(code: "ABC123")
/// print("Tokens/sec: \(report.tokensPerSecond)")
/// ```
public actor PairingManager {

    // MARK: - Properties

    private let apiClient: APIClient
    private let configuration: OctomilConfiguration
    private let logger: Logger

    /// Default number of warm inferences during benchmarking.
    /// 50 gives meaningful p95/p99 percentiles.
    private static let defaultWarmInferenceCount = 50

    /// Default polling interval in seconds when waiting for deployment.
    private static let defaultPollInterval: TimeInterval = 2.0

    // MARK: - Initialization

    /// Creates a new pairing manager.
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    public init(apiClient: APIClient, configuration: OctomilConfiguration = .standard) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingManager")
    }

    /// Convenience initializer that creates its own API client.
    /// - Parameters:
    ///   - serverURL: Base URL of the Octomil server.
    ///   - configuration: SDK configuration.
    public init(serverURL: URL, configuration: OctomilConfiguration = .standard) {
        self.apiClient = APIClient(serverURL: serverURL, configuration: configuration)
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingManager")
    }

    /// Test-only initializer with injected URLSession configuration.
    internal init(
        serverURL: URL,
        configuration: OctomilConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.apiClient = APIClient(
            serverURL: serverURL,
            configuration: configuration,
            sessionConfiguration: sessionConfiguration
        )
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingManager")
    }

    // MARK: - Public API

    /// Connect to a pairing session using the code from a QR scan.
    ///
    /// Sends device capabilities to the server so it can select the
    /// optimal model variant for this hardware.
    ///
    /// - Parameters:
    ///   - code: Pairing code from the QR scan.
    ///   - deviceCapabilities: Device hardware info. Defaults to auto-detected.
    /// - Returns: The pairing session info.
    /// - Throws: ``PairingError`` or ``OctomilError``.
    public func connect(
        code: String,
        deviceCapabilities: PairingDeviceCapabilities = .current()
    ) async throws -> PairingSession {
        if configuration.enableLogging {
            logger.info("Connecting to pairing session: \(code)")
        }

        let session = try await apiClient.connectToPairing(
            code: code,
            deviceId: UUID().uuidString,
            platform: "ios",
            deviceName: deviceCapabilities.deviceName,
            chipFamily: deviceCapabilities.chipFamily,
            ramGB: deviceCapabilities.ramGB,
            osVersion: deviceCapabilities.osVersion,
            npuAvailable: deviceCapabilities.npuAvailable,
            gpuAvailable: deviceCapabilities.gpuAvailable
        )

        if configuration.enableLogging {
            logger.info("Connected to session \(session.id), model: \(session.modelName)")
        }

        TelemetryQueue.shared?.reportFunnelEvent(
            stage: "app_pair",
            success: true,
            deviceId: UUID().uuidString,
            platform: "ios"
        )

        return session
    }

    /// Poll for deployment status until a model is ready to download.
    ///
    /// Blocks until the session reaches `deploying` or `done` status,
    /// or until the timeout expires.
    ///
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - timeout: Maximum time to wait in seconds (default: 300).
    /// - Returns: Deployment info with download URL.
    /// - Throws: ``PairingError/deploymentTimeout`` if timeout expires.
    ///           ``PairingError/sessionExpired`` if session expires.
    ///           ``PairingError/sessionCancelled`` if session is cancelled.
    public func waitForDeployment(
        code: String,
        timeout: TimeInterval = 300
    ) async throws -> DeploymentInfo {
        if configuration.enableLogging {
            logger.info("Waiting for deployment on session \(code), timeout=\(timeout)s")
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let session = try await apiClient.getPairingSession(code: code)

            switch session.status {
            case .deploying, .done:
                guard let downloadURL = session.downloadURL,
                      let format = session.downloadFormat else {
                    throw PairingError.invalidDeployment(
                        reason: "Session is deploying but missing download URL or format"
                    )
                }

                let deployment = DeploymentInfo(
                    modelName: session.modelName,
                    modelVersion: session.modelVersion ?? "latest",
                    downloadURL: downloadURL,
                    format: format,
                    quantization: session.quantization,
                    executor: session.executor,
                    sizeBytes: session.downloadSizeBytes
                )

                if configuration.enableLogging {
                    logger.info("Deployment ready: \(session.modelName) (\(format))")
                }

                return deployment

            case .expired:
                throw PairingError.sessionExpired

            case .cancelled:
                throw PairingError.sessionCancelled

            case .pending, .connected:
                // Keep polling
                try await Task.sleep(nanoseconds: UInt64(Self.defaultPollInterval * 1_000_000_000))
            }
        }

        throw PairingError.deploymentTimeout
    }

    /// Download the model specified in the deployment, run benchmarks,
    /// and report results to the server.
    ///
    /// - Parameter deployment: Deployment info from ``waitForDeployment(code:timeout:)``.
    /// - Returns: Benchmark report with performance metrics.
    /// - Throws: ``PairingError`` if download or benchmarking fails.
    public func executeDeployment(_ deployment: DeploymentInfo) async throws -> BenchmarkReport {
        if configuration.enableLogging {
            logger.info("Executing deployment: \(deployment.modelName)")
        }

        // Download model
        guard let downloadURL = URL(string: deployment.downloadURL) else {
            throw PairingError.invalidDeployment(reason: "Invalid download URL: \(deployment.downloadURL)")
        }

        let modelLoadStart = Date()
        let modelData: Data
        do {
            modelData = try await apiClient.downloadData(from: downloadURL)
        } catch {
            throw PairingError.downloadFailed(reason: error.localizedDescription)
        }

        // Save to temp file and compile
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(
            "\(deployment.modelName)_\(deployment.modelVersion).mlmodel"
        )
        try modelData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let compiledURL: URL
        do {
            compiledURL = try await MLModel.compileModel(at: tempFile)
        } catch {
            throw PairingError.benchmarkFailed(reason: "Model compilation failed: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: compiledURL) }

        let mlModel: MLModel
        do {
            mlModel = try MLModel(contentsOf: compiledURL)
        } catch {
            throw PairingError.benchmarkFailed(reason: "Model loading failed: \(error.localizedDescription)")
        }

        let modelLoadTimeMs = Date().timeIntervalSince(modelLoadStart) * 1000

        // Run benchmarks (pass compiledURL for CPU-only delegate comparison)
        let report = try runBenchmarks(
            model: mlModel,
            compiledURL: compiledURL,
            modelName: deployment.modelName,
            modelLoadTimeMs: modelLoadTimeMs
        )

        if configuration.enableLogging {
            let tps = String(format: "%.1f", report.tokensPerSecond)
            logger.info("Benchmark complete: \(tps) tokens/sec, p50=\(String(format: "%.1f", report.p50LatencyMs))ms")
        }

        return report
    }

    /// Submit benchmark results to the server.
    ///
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - report: Benchmark report to submit.
    public func submitBenchmark(code: String, report: BenchmarkReport) async throws {
        try await apiClient.submitPairingBenchmark(code: code, report: report)
    }

    /// Full pairing flow: connect, wait for deployment, download, benchmark, and report.
    ///
    /// This is the recommended single-call API for the pairing flow.
    ///
    /// - Parameters:
    ///   - code: Pairing code from QR scan.
    ///   - deviceCapabilities: Device hardware info. Defaults to auto-detected.
    ///   - timeout: Maximum time to wait for deployment in seconds.
    /// - Returns: Benchmark report with full performance metrics.
    /// - Throws: ``PairingError`` or ``OctomilError``.
    public func pair(
        code: String,
        deviceCapabilities: PairingDeviceCapabilities = .current(),
        timeout: TimeInterval = 300
    ) async throws -> BenchmarkReport {
        if configuration.enableLogging {
            logger.info("Starting full pairing flow for code: \(code)")
        }

        // Step 1: Connect
        _ = try await connect(code: code, deviceCapabilities: deviceCapabilities)

        // Step 2: Wait for deployment
        let deployment = try await waitForDeployment(code: code, timeout: timeout)

        // Step 3: Download, benchmark
        let report = try await executeDeployment(deployment)

        // Step 4: Submit results
        try await apiClient.submitPairingBenchmark(code: code, report: report)

        if configuration.enableLogging {
            logger.info("Pairing flow complete for code: \(code)")
        }

        return report
    }

    // MARK: - Benchmarking

    /// Runs the benchmark sequence on a compiled model.
    ///
    /// Flow:
    /// 1. Cold inference (captures TTFT)
    /// 2. Delegate auto-selection (warm pass vs CPU-only pass)
    /// 3. 50 warm inferences for percentile calculations
    /// 4. Assemble the benchmark report
    private func runBenchmarks(
        model: MLModel,
        compiledURL: URL,
        modelName: String,
        modelLoadTimeMs: Double
    ) throws -> BenchmarkReport {
        // Create dummy input matching model's expected shape
        guard let dummyInput = createDummyInput(for: model) else {
            throw PairingError.benchmarkFailed(reason: "Could not create dummy input for model")
        }

        // Capture memory before
        let memoryBefore = availableMemoryBytes()

        // Cold inference (TTFT)
        let coldStart = Date()
        _ = try? model.prediction(from: dummyInput)
        let coldInferenceMs = Date().timeIntervalSince(coldStart) * 1000

        // Delegate auto-selection: warm pass then CPU-only comparison
        let warmupStart = Date()
        _ = try? model.prediction(from: dummyInput)
        let warmPassMs = Date().timeIntervalSince(warmupStart) * 1000

        var cpuInferenceMs: Double? = nil
        let cpuConfig = MLModelConfiguration()
        cpuConfig.computeUnits = .cpuOnly
        if let cpuModel = try? MLModel(contentsOf: compiledURL, configuration: cpuConfig) {
            let cpuStart = Date()
            _ = try? cpuModel.prediction(from: dummyInput)
            cpuInferenceMs = Date().timeIntervalSince(cpuStart) * 1000
        }

        let hasNPU = detectNPUAvailable()
        var activeDelegate = hasNPU ? "neural_engine" : "gpu"
        var disabledDelegates: [String] = []

        // If CPU is faster than the hardware-accelerated warm pass, disable the accelerator
        if let cpuMs = cpuInferenceMs, cpuMs < warmPassMs {
            if hasNPU {
                disabledDelegates.append("neural_engine")
            } else {
                disabledDelegates.append("gpu")
            }
            activeDelegate = "cpu"
        }

        if configuration.enableLogging {
            let warmStr = String(format: "%.1f", warmPassMs)
            let cpuStr = cpuInferenceMs.map { String(format: "%.1f", $0) } ?? "n/a"
            let disabledStr = disabledDelegates.joined(separator: ",")
            logger.info("Delegate selected: \(activeDelegate), disabled: [\(disabledStr)], warm=\(warmStr)ms, cpu=\(cpuStr)ms")
        }

        // Warm inferences (50 iterations for meaningful percentiles)
        var latencies: [Double] = []
        for _ in 0..<Self.defaultWarmInferenceCount {
            let start = Date()
            _ = try? model.prediction(from: dummyInput)
            let latencyMs = Date().timeIntervalSince(start) * 1000
            latencies.append(latencyMs)
        }

        // Capture memory after
        let memoryAfter = availableMemoryBytes()
        let memoryPeakBytes = max(0, memoryBefore - memoryAfter)

        // Compute percentiles
        let sortedLatencies = latencies.sorted()
        let p50 = percentile(sortedLatencies, p: 0.50)
        let p95 = percentile(sortedLatencies, p: 0.95)
        let p99 = percentile(sortedLatencies, p: 0.99)
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let tokensPerSecond = avgLatency > 0 ? 1000.0 / avgLatency : 0

        // Warmup inference (best of warm latencies)
        let warmInferenceMs = sortedLatencies.first ?? coldInferenceMs

        // Device info
        let caps = PairingDeviceCapabilities.current()

        // Battery
        let batteryLevel = currentBatteryLevel()

        // Thermal state
        let thermalState = currentThermalState()

        // Total inference count: 1 cold + 1 warm-pass + 1 CPU-pass (if run) + N warm
        let totalInferences = Self.defaultWarmInferenceCount + 2 + (cpuInferenceMs != nil ? 1 : 0)

        return BenchmarkReport(
            modelName: modelName,
            deviceName: caps.deviceName,
            chipFamily: caps.chipFamily,
            ramGB: caps.ramGB,
            osVersion: caps.osVersion,
            ttftMs: coldInferenceMs,
            tpotMs: avgLatency,
            tokensPerSecond: tokensPerSecond,
            p50LatencyMs: p50,
            p95LatencyMs: p95,
            p99LatencyMs: p99,
            memoryPeakBytes: memoryPeakBytes,
            inferenceCount: totalInferences,
            modelLoadTimeMs: modelLoadTimeMs,
            coldInferenceMs: coldInferenceMs,
            warmInferenceMs: warmInferenceMs,
            activeDelegate: activeDelegate,
            disabledDelegates: disabledDelegates,
            batteryLevel: batteryLevel,
            thermalState: thermalState
        )
    }

    // MARK: - Helpers

    /// Creates a dummy MLFeatureProvider matching the model's input description.
    private func createDummyInput(for model: MLModel) -> MLFeatureProvider? {
        let inputDescs = model.modelDescription.inputDescriptionsByName
        var features: [String: MLFeatureValue] = [:]

        for (name, desc) in inputDescs {
            if let constraint = desc.multiArrayConstraint {
                guard let array = try? MLMultiArray(shape: constraint.shape, dataType: .float32) else {
                    return nil
                }
                features[name] = MLFeatureValue(multiArray: array)
            }
        }

        guard !features.isEmpty else { return nil }
        return try? MLDictionaryFeatureProvider(dictionary: features)
    }

    /// Computes a percentile value from sorted data.
    private func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[index]
    }

    /// Returns available memory in bytes.
    ///
    /// Uses `os_proc_available_memory()` on iOS/tvOS/watchOS.
    /// Falls back to `ProcessInfo.physicalMemory` on macOS.
    private func availableMemoryBytes() -> Int {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return Int(os_proc_available_memory())
        #else
        return Int(ProcessInfo.processInfo.physicalMemory)
        #endif
    }

    /// Returns current battery level as a Double (0.0 - 1.0), or nil if unavailable.
    private func currentBatteryLevel() -> Double? {
        #if canImport(UIKit) && os(iOS)
        // UIDevice.current requires main thread, but we're inside an actor.
        // Use a synchronous DispatchQueue.main.sync call to safely read it.
        let level: Float = DispatchQueue.main.sync {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let l = UIDevice.current.batteryLevel
            UIDevice.current.isBatteryMonitoringEnabled = false
            return l
        }
        return level >= 0 ? Double(level) : nil
        #else
        return nil
        #endif
    }

    /// Detects whether the Neural Processing Unit is available.
    ///
    /// On real iOS hardware (A11+) the Neural Engine is always present.
    /// Returns false on macOS and Simulator.
    private func detectNPUAvailable() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif os(iOS) || os(tvOS) || os(watchOS)
        return true
        #else
        return false
        #endif
    }

    /// Returns current thermal state as a string.
    private func currentThermalState() -> String {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}

import Foundation

// MARK: - Pairing Session

/// Represents a pairing session between the dashboard and a device.
///
/// Created when a user scans a QR code from the Octomil dashboard.
/// The session tracks the lifecycle from initial scan through
/// model deployment and benchmarking.
public struct PairingSession: Codable, Sendable {
    /// Server-assigned session UUID.
    public let id: String
    /// Short pairing code from the QR scan.
    public let code: String
    /// Name of the model to deploy.
    public let modelName: String
    /// Optional model version (nil means latest).
    public let modelVersion: String?
    /// Current session status.
    public let status: PairingStatus
    /// Pre-signed URL to download the model (available when status is `deploying` or `done`).
    public let downloadURL: String?
    /// Model format (e.g. "coreml", "onnx", "mnn").
    public let downloadFormat: String?
    /// Size of the model download in bytes.
    public let downloadSizeBytes: Int?
    /// Server-assigned device class (e.g. "flagship", "high", "mid", "low").
    public let deviceClass: String?
    /// Quantization method applied to the model (e.g. "q4", "q8", "fp16").
    public let quantization: String?
    /// Inference executor (e.g. "coreml", "mnn").
    public let executor: String?
    /// Multi-file resources for this deployment, if any.
    public let resources: [DownloadResource]?
    /// Organization ID that owns this pairing session.
    public let orgId: String?
    /// Device access token issued during pairing connect (for subsequent API calls).
    public let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case modelName = "model_name"
        case modelVersion = "model_version"
        case status
        case downloadURL = "download_url"
        case downloadFormat = "download_format"
        case downloadSizeBytes = "download_size_bytes"
        case deviceClass = "device_class"
        case quantization
        case executor
        case resources
        case orgId = "org_id"
        case accessToken = "access_token"
    }
}

// MARK: - Download Resource

/// A single downloadable resource within a multi-file deployment.
///
/// Resources are downloaded in ``loadOrder`` sequence and placed into
/// a model directory using their ``filename``.
public struct DownloadResource: Codable, Sendable {
    /// Resource kind (e.g. "weights", "tokenizer", "config").
    public let kind: String
    /// Pre-signed download URI.
    public let uri: String
    /// Filename to use when saving the resource locally.
    public let filename: String
    /// Order in which this resource should be loaded (0-based).
    public let loadOrder: Int
    /// Size in bytes, if known.
    public let sizeBytes: Int?
    /// SHA-256 checksum of the file contents, if known.
    public let checksumSha256: String?

    enum CodingKeys: String, CodingKey {
        case kind, uri, filename
        case loadOrder = "load_order"
        case sizeBytes = "size_bytes"
        case checksumSha256 = "checksum_sha256"
    }
}

// MARK: - Pairing Status

/// Status of a pairing session.
public enum PairingStatus: String, Codable, Sendable {
    /// Session created, waiting for a device to connect.
    case pending
    /// Device connected, server is preparing the deployment.
    case connected
    /// Model is being prepared / ready for download.
    case deploying
    /// Benchmarks submitted, session complete.
    case done
    /// Session expired without completion.
    case expired
    /// Session was manually cancelled.
    case cancelled
    /// Server encountered an error during deployment.
    case error
}

// MARK: - Deployment Info

/// Information needed to download and benchmark a model.
///
/// Extracted from a ``PairingSession`` once it reaches the `deploying` state.
public struct DeploymentInfo: Sendable {
    /// Model name.
    public let modelName: String
    /// Resolved model version.
    public let modelVersion: String
    /// Pre-signed download URL.
    public let downloadURL: String
    /// Model format.
    public let format: String
    /// Quantization method, if any.
    public let quantization: String?
    /// Inference executor, if any.
    public let executor: String?
    /// Download size in bytes, if known.
    public let sizeBytes: Int?
    /// Multi-file resources for this deployment, if any.
    public let resources: [DownloadResource]?

    public init(
        modelName: String,
        modelVersion: String,
        downloadURL: String,
        format: String,
        quantization: String? = nil,
        executor: String? = nil,
        sizeBytes: Int? = nil,
        resources: [DownloadResource]? = nil
    ) {
        self.modelName = modelName
        self.modelVersion = modelVersion
        self.downloadURL = downloadURL
        self.format = format
        self.quantization = quantization
        self.executor = executor
        self.sizeBytes = sizeBytes
        self.resources = resources
    }
}

// MARK: - Benchmark Report

/// Performance benchmark results from running a model on this device.
///
/// Collected during the pairing flow and submitted to the server
/// so the dashboard can display real device performance data.
public struct BenchmarkReport: Codable, Sendable {
    // -- Model --
    /// Name of the benchmarked model.
    public let modelName: String

    // -- Device --
    /// Human-readable device name (e.g. "iPhone 15 Pro").
    public let deviceName: String
    /// SoC family (e.g. "A17 Pro").
    public let chipFamily: String
    /// Total RAM in gigabytes.
    public let ramGB: Double
    /// OS version string (e.g. "17.4").
    public let osVersion: String

    // -- Performance --
    /// Time to first token in milliseconds.
    public let ttftMs: Double
    /// Time per output token in milliseconds.
    public let tpotMs: Double
    /// Throughput in tokens (or inferences) per second.
    public let tokensPerSecond: Double
    /// Median latency in milliseconds.
    public let p50LatencyMs: Double
    /// 95th percentile latency in milliseconds.
    public let p95LatencyMs: Double
    /// 99th percentile latency in milliseconds.
    public let p99LatencyMs: Double
    /// Peak memory usage in bytes during inference.
    public let memoryPeakBytes: Int
    /// Number of inferences run during benchmarking.
    public let inferenceCount: Int

    // -- Warmup --
    /// Time to load and compile the model in milliseconds.
    public let modelLoadTimeMs: Double
    /// First (cold) inference latency in milliseconds.
    public let coldInferenceMs: Double
    /// Steady-state (warm) inference latency in milliseconds.
    public let warmInferenceMs: Double

    // -- Token Metrics --
    /// Number of prompt tokens processed, if applicable.
    public let promptTokens: Int?
    /// Number of completion tokens generated, if applicable.
    public let completionTokens: Int?
    /// Context length used for inference, if applicable.
    public let contextLength: Int?
    /// Total tokens (prompt + completion), if applicable.
    public let totalTokens: Int?

    // -- Delegate Selection --
    /// Which compute delegate was selected after warmup: "neural_engine", "gpu", or "cpu".
    public let activeDelegate: String?
    /// Delegates that were disabled during warmup cascade.
    public let disabledDelegates: [String]?

    // -- Context --
    /// Device battery level at benchmark time (0.0-1.0), or nil if unavailable.
    public let batteryLevel: Double?
    /// Thermal state at benchmark time (e.g. "nominal", "fair", "serious", "critical").
    public let thermalState: String?

    // -- Model Persistence (not encoded) --
    /// URL of the compiled model persisted to the cache directory after benchmarking.
    /// Set by ``PairingManager`` after a successful deployment.
    public var persistedModelURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case deviceName = "device_name"
        case chipFamily = "chip_family"
        case ramGB = "ram_gb"
        case osVersion = "os_version"
        case ttftMs = "ttft_ms"
        case tpotMs = "tpot_ms"
        case tokensPerSecond = "tokens_per_second"
        case p50LatencyMs = "p50_latency_ms"
        case p95LatencyMs = "p95_latency_ms"
        case p99LatencyMs = "p99_latency_ms"
        case memoryPeakBytes = "memory_peak_bytes"
        case inferenceCount = "inference_count"
        case modelLoadTimeMs = "model_load_time_ms"
        case coldInferenceMs = "cold_inference_ms"
        case warmInferenceMs = "warm_inference_ms"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case contextLength = "context_length"
        case totalTokens = "total_tokens"
        case activeDelegate = "active_delegate"
        case disabledDelegates = "disabled_delegates"
        case batteryLevel = "battery_level"
        case thermalState = "thermal_state"
    }

    public init(
        modelName: String,
        deviceName: String,
        chipFamily: String,
        ramGB: Double,
        osVersion: String,
        ttftMs: Double,
        tpotMs: Double,
        tokensPerSecond: Double,
        p50LatencyMs: Double,
        p95LatencyMs: Double,
        p99LatencyMs: Double,
        memoryPeakBytes: Int,
        inferenceCount: Int,
        modelLoadTimeMs: Double,
        coldInferenceMs: Double,
        warmInferenceMs: Double,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        contextLength: Int? = nil,
        totalTokens: Int? = nil,
        activeDelegate: String? = nil,
        disabledDelegates: [String]? = nil,
        batteryLevel: Double? = nil,
        thermalState: String? = nil
    ) {
        self.modelName = modelName
        self.deviceName = deviceName
        self.chipFamily = chipFamily
        self.ramGB = ramGB
        self.osVersion = osVersion
        self.ttftMs = ttftMs
        self.tpotMs = tpotMs
        self.tokensPerSecond = tokensPerSecond
        self.p50LatencyMs = p50LatencyMs
        self.p95LatencyMs = p95LatencyMs
        self.p99LatencyMs = p99LatencyMs
        self.memoryPeakBytes = memoryPeakBytes
        self.inferenceCount = inferenceCount
        self.modelLoadTimeMs = modelLoadTimeMs
        self.coldInferenceMs = coldInferenceMs
        self.warmInferenceMs = warmInferenceMs
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.contextLength = contextLength
        self.totalTokens = totalTokens
        self.activeDelegate = activeDelegate
        self.disabledDelegates = disabledDelegates
        self.batteryLevel = batteryLevel
        self.thermalState = thermalState
    }
}

// MARK: - Deployment Result

/// Result of executing a model deployment (download + persistence).
///
/// Returned by ``PairingManager/executeDeployment(_:progress:)`` after
/// the model has been downloaded and persisted to the cache directory.
/// Unlike ``BenchmarkReport``, this does not contain performance metrics --
/// real benchmarks are collected later by the Deploy (engine routing) layer.
public struct DeploymentResult: Sendable {
    /// Name of the deployed model.
    public let modelName: String
    /// Resolved model version.
    public let modelVersion: String
    /// URL of the persisted model directory on disk.
    public let persistedModelURL: URL
    /// Time to download the model in milliseconds.
    public let downloadTimeMs: Double
    /// Inference executor specified by the server, if any (e.g. "coreml", "mnn").
    public let executor: String?
    /// Resource kind → filename mapping built from ``DownloadResource`` entries.
    ///
    /// Consumers use this to resolve individual files (weights, tokenizer, etc.)
    /// within the persisted model directory.
    public let resourceBindings: [String: String]

    public init(
        modelName: String,
        modelVersion: String,
        persistedModelURL: URL,
        downloadTimeMs: Double,
        executor: String? = nil,
        resourceBindings: [String: String] = [:]
    ) {
        self.modelName = modelName
        self.modelVersion = modelVersion
        self.persistedModelURL = persistedModelURL
        self.downloadTimeMs = downloadTimeMs
        self.executor = executor
        self.resourceBindings = resourceBindings
    }
}

// MARK: - Pairing Device Capabilities

/// Hardware and software capabilities of the device, collected during pairing.
///
/// Sent to the server when connecting to a pairing session so the server
/// can select the optimal model variant for this device.
public struct PairingDeviceCapabilities: Sendable {
    /// Human-readable device name (e.g. "iPhone 15 Pro").
    public let deviceName: String
    /// SoC family (e.g. "A17 Pro").
    public let chipFamily: String
    /// Total RAM in gigabytes.
    public let ramGB: Double
    /// OS version string (e.g. "17.4").
    public let osVersion: String
    /// Whether the Neural Processing Unit is available.
    public let npuAvailable: Bool
    /// Whether the GPU is available for ML workloads.
    public let gpuAvailable: Bool
    /// Device locale (e.g. "en_US").
    public let locale: String?
    /// Device region/country code (e.g. "US").
    public let region: String?
    /// Device timezone identifier (e.g. "America/New_York").
    public let timezone: String?

    public init(
        deviceName: String,
        chipFamily: String,
        ramGB: Double,
        osVersion: String,
        npuAvailable: Bool,
        gpuAvailable: Bool,
        locale: String? = nil,
        region: String? = nil,
        timezone: String? = nil
    ) {
        self.deviceName = deviceName
        self.chipFamily = chipFamily
        self.ramGB = ramGB
        self.osVersion = osVersion
        self.npuAvailable = npuAvailable
        self.gpuAvailable = gpuAvailable
        self.locale = locale
        self.region = region
        self.timezone = timezone
    }

    /// Auto-detect capabilities from the current device hardware.
    public static func current() -> PairingDeviceCapabilities {
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Double(ramBytes) / (1024 * 1024 * 1024)

        let osVersion = currentOSVersion()
        let deviceName = currentDeviceName()
        let chipFamily = detectChipFamily()

        let currentLocale = Locale.current
        let localeId = currentLocale.identifier
        let regionCode = currentLocale.region?.identifier
        let timezoneId = TimeZone.current.identifier

        return PairingDeviceCapabilities(
            deviceName: deviceName,
            chipFamily: chipFamily,
            ramGB: ramGB,
            osVersion: osVersion,
            npuAvailable: detectNPU(),
            gpuAvailable: true,
            locale: localeId,
            region: regionCode,
            timezone: timezoneId
        )
    }

    // MARK: - Private detection helpers

    private static func currentOSVersion() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static func currentDeviceName() -> String {
        #if os(iOS) || os(tvOS)
        let machine = machineIdentifier()
        return mapMachineToName(machine)
        #else
        return "Mac"
        #endif
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        } ?? "Unknown"
    }

    /// Maps machine identifier to human-readable device name.
    private static func mapMachineToName(_ machine: String) -> String {
        // iPhone mappings
        let mapping: [String: String] = [
            // iPhone 13
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            // iPhone 14
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            // iPhone 15
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            // iPhone 16
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            // iPad Pro M-series
            "iPad13,4": "iPad Pro 11-inch (3rd gen)",
            "iPad13,5": "iPad Pro 11-inch (3rd gen)",
            "iPad14,3": "iPad Pro 11-inch (4th gen)",
            "iPad14,4": "iPad Pro 11-inch (4th gen)",
            // Simulator
            "x86_64": "Simulator",
            "arm64": "Simulator",
        ]

        if let name = mapping[machine] {
            return name
        }

        // Fallback: parse the prefix
        if machine.hasPrefix("iPhone") {
            return "iPhone"
        } else if machine.hasPrefix("iPad") {
            return "iPad"
        }

        return machine
    }

    /// Maps machine identifier to SoC family.
    private static func detectChipFamily() -> String {
        let machine = machineIdentifier()

        // A17 Pro: iPhone 15 Pro / Pro Max
        if machine.hasPrefix("iPhone16,1") || machine.hasPrefix("iPhone16,2") {
            return "A17 Pro"
        }
        // A18 Pro: iPhone 16 Pro / Pro Max
        if machine.hasPrefix("iPhone17,1") || machine.hasPrefix("iPhone17,2") {
            return "A18 Pro"
        }
        // A18: iPhone 16 / 16 Plus
        if machine.hasPrefix("iPhone17,3") || machine.hasPrefix("iPhone17,4") {
            return "A18"
        }
        // A16: iPhone 15 / 15 Plus, iPhone 14 Pro / Pro Max
        if machine.hasPrefix("iPhone15,2") || machine.hasPrefix("iPhone15,3") ||
           machine.hasPrefix("iPhone15,4") || machine.hasPrefix("iPhone15,5") {
            return "A16 Bionic"
        }
        // A15: iPhone 14 / 14 Plus, iPhone 13 family
        if machine.hasPrefix("iPhone14,") {
            return "A15 Bionic"
        }

        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        // M-series iPads/Macs
        if machine.hasPrefix("iPad14,") || machine.hasPrefix("iPad16,") {
            return "M-series"
        }
        return "Unknown"
        #endif
    }

    /// Detects whether the Neural Processing Unit is available.
    ///
    /// All Apple SoCs from A11 Bionic (iPhone X, 2017) onward include
    /// a Neural Engine, so on iOS 15+ this is always true for real hardware.
    private static func detectNPU() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}

// MARK: - Pairing Error

/// Errors specific to the pairing flow.
public enum PairingError: LocalizedError, Sendable {
    /// The pairing code is invalid or the session was not found.
    case sessionNotFound(code: String)
    /// The session has expired.
    case sessionExpired
    /// The session was cancelled.
    case sessionCancelled
    /// Timed out waiting for deployment.
    case deploymentTimeout
    /// The deployment info is missing required fields.
    case invalidDeployment(reason: String)
    /// Model download failed during pairing.
    case downloadFailed(reason: String)
    /// Benchmark execution failed.
    case benchmarkFailed(reason: String)
    /// The pairing session was already used / model already deployed.
    case sessionAlreadyUsed

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let code):
            return "Pairing session not found for code: \(code)"
        case .sessionExpired:
            return "Pairing session has expired."
        case .sessionCancelled:
            return "Pairing session was cancelled."
        case .deploymentTimeout:
            return "Timed out waiting for model deployment."
        case .invalidDeployment(let reason):
            return "Invalid deployment: \(reason)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .benchmarkFailed(let reason):
            return "Benchmark failed: \(reason)"
        case .sessionAlreadyUsed:
            return "This pairing session has already been used."
        }
    }
}

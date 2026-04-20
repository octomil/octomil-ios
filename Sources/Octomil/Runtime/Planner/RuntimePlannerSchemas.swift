import Foundation

// MARK: - InstalledRuntime

/// A locally-installed inference engine detected on this device.
///
/// Mirrors the server contract `InstalledRuntime` schema.
public struct InstalledRuntime: Codable, Sendable, Equatable {
    /// Engine identifier (e.g. "coreml", "mlx-lm", "llama.cpp").
    public let engine: String
    /// Engine version string, if known.
    public let version: String?
    /// Whether the engine is currently usable.
    public let available: Bool
    /// Hardware accelerator used by this engine (e.g. "metal", "ane").
    public let accelerator: String?
    /// Arbitrary metadata about the engine installation.
    public let metadata: [String: String]

    public init(
        engine: String,
        version: String? = nil,
        available: Bool = true,
        accelerator: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.engine = RuntimeEngineID.canonical(engine)
        self.version = version
        self.available = available
        self.accelerator = accelerator
        self.metadata = metadata
    }
}

/// Canonical runtime engine identifiers shared with the server planner.
///
/// Older SDKs and examples used aliases such as `mlx`, `llamacpp`, and
/// `llama_cpp`. Normalize at SDK boundaries so device profiles, server plans,
/// cache keys, and telemetry all speak the same wire vocabulary.
public enum RuntimeEngineID {
    private static let aliases: [String: String] = [
        "mlx": "mlx-lm",
        "mlx_lm": "mlx-lm",
        "mlxlm": "mlx-lm",
        "llamacpp": "llama.cpp",
        "llama_cpp": "llama.cpp",
        "llama-cpp": "llama.cpp",
        "whisper": "whisper.cpp",
        "whispercpp": "whisper.cpp",
        "whisper_cpp": "whisper.cpp",
        "whisper-cpp": "whisper.cpp",
    ]

    public static func canonical(_ engine: String) -> String {
        let normalized = engine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliases[normalized] ?? normalized
    }

    public static func canonical(_ engine: String?) -> String? {
        guard let engine else { return nil }
        return canonical(engine)
    }
}

// MARK: - DeviceRuntimeProfile

/// Hardware and software profile sent to the server planner endpoint.
///
/// Mirrors the server contract `DeviceRuntimeProfile` schema.
public struct DeviceRuntimeProfile: Codable, Sendable, Equatable {
    /// SDK platform identifier.
    public let sdk: String
    /// SDK version string.
    public let sdkVersion: String
    /// Operating system platform (e.g. "iOS", "macOS").
    public let platform: String
    /// CPU architecture (e.g. "arm64").
    public let arch: String
    /// OS version string.
    public let osVersion: String?
    /// Chip/SoC identifier (e.g. "Apple M2", "A17 Pro").
    public let chip: String?
    /// Total RAM in bytes.
    public let ramTotalBytes: Int64?
    /// Number of GPU cores, if known.
    public let gpuCoreCount: Int?
    /// Available hardware accelerators (e.g. ["metal", "ane"]).
    public let accelerators: [String]
    /// Locally-installed inference engines.
    public let installedRuntimes: [InstalledRuntime]

    enum CodingKeys: String, CodingKey {
        case sdk
        case sdkVersion = "sdk_version"
        case platform
        case arch
        case osVersion = "os_version"
        case chip
        case ramTotalBytes = "ram_total_bytes"
        case gpuCoreCount = "gpu_core_count"
        case accelerators
        case installedRuntimes = "installed_runtimes"
    }

    public init(
        sdk: String = "ios",
        sdkVersion: String = OctomilVersion.current,
        platform: String,
        arch: String,
        osVersion: String? = nil,
        chip: String? = nil,
        ramTotalBytes: Int64? = nil,
        gpuCoreCount: Int? = nil,
        accelerators: [String] = [],
        installedRuntimes: [InstalledRuntime] = []
    ) {
        self.sdk = sdk
        self.sdkVersion = sdkVersion
        self.platform = platform
        self.arch = arch
        self.osVersion = osVersion
        self.chip = chip
        self.ramTotalBytes = ramTotalBytes
        self.gpuCoreCount = gpuCoreCount
        self.accelerators = accelerators
        self.installedRuntimes = installedRuntimes
    }
}

// MARK: - RuntimeArtifactPlan

/// Artifact recommendation from the server planner.
public struct RuntimeArtifactPlan: Codable, Sendable, Equatable {
    /// Model identifier.
    public let modelId: String
    /// Server-assigned artifact ID.
    public let artifactId: String?
    /// Model version string.
    public let modelVersion: String?
    /// Model format (e.g. "mlmodelc", "gguf", "safetensors").
    public let format: String?
    /// Quantization level (e.g. "q4_k_m", "int8").
    public let quantization: String?
    /// Download URI for the artifact.
    public let uri: String?
    /// Content digest (e.g. SHA-256 hex).
    public let digest: String?
    /// Artifact size in bytes.
    public let sizeBytes: Int64?
    /// Minimum RAM required in bytes.
    public let minRamBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case artifactId = "artifact_id"
        case modelVersion = "model_version"
        case format
        case quantization
        case uri
        case digest
        case sizeBytes = "size_bytes"
        case minRamBytes = "min_ram_bytes"
    }

    public init(
        modelId: String,
        artifactId: String? = nil,
        modelVersion: String? = nil,
        format: String? = nil,
        quantization: String? = nil,
        uri: String? = nil,
        digest: String? = nil,
        sizeBytes: Int64? = nil,
        minRamBytes: Int64? = nil
    ) {
        self.modelId = modelId
        self.artifactId = artifactId
        self.modelVersion = modelVersion
        self.format = format
        self.quantization = quantization
        self.uri = uri
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.minRamBytes = minRamBytes
    }
}

// MARK: - RuntimeCandidatePlan

/// A single candidate in a runtime plan (local or cloud).
public struct RuntimeCandidatePlan: Codable, Sendable, Equatable {
    /// Where this candidate would run.
    public let locality: RuntimeLocality
    /// Candidate priority (lower is higher priority).
    public let priority: Int
    /// Server confidence score (0.0-1.0).
    public let confidence: Double
    /// Human-readable reason for this recommendation.
    public let reason: String
    /// Engine to use (e.g. "coreml", "mlx-lm", "llama.cpp").
    public let engine: String?
    /// Semver constraint on engine version.
    public let engineVersionConstraint: String?
    /// Recommended artifact to download/use.
    public let artifact: RuntimeArtifactPlan?
    /// Whether a local benchmark is required before using this candidate.
    public let benchmarkRequired: Bool
    /// Per-request gates attached by the server planner.
    public let gates: [CandidateGate]

    enum CodingKeys: String, CodingKey {
        case locality
        case priority
        case confidence
        case reason
        case engine
        case engineVersionConstraint = "engine_version_constraint"
        case artifact
        case benchmarkRequired = "benchmark_required"
        case gates
    }

    public init(
        locality: RuntimeLocality,
        priority: Int,
        confidence: Double,
        reason: String,
        engine: String? = nil,
        engineVersionConstraint: String? = nil,
        artifact: RuntimeArtifactPlan? = nil,
        benchmarkRequired: Bool = false,
        gates: [CandidateGate] = []
    ) {
        self.locality = locality
        self.priority = priority
        self.confidence = confidence
        self.reason = reason
        self.engine = engine
        self.engineVersionConstraint = engineVersionConstraint
        self.artifact = artifact
        self.benchmarkRequired = benchmarkRequired
        self.gates = gates
    }
}

// MARK: - RuntimeLocality

/// Where inference runs: on-device or in the cloud.
public enum RuntimeLocality: String, Codable, Sendable, Equatable {
    case local
    case cloud
}

// MARK: - RuntimePlanResponse

/// Full plan response from the server planner API.
///
/// Mirrors the server contract `RuntimePlanResponse` schema.
public struct RuntimePlanResponse: Codable, Sendable, Equatable {
    /// Model identifier the plan was generated for.
    public let model: String
    /// Capability the plan was generated for (e.g. "text", "embeddings").
    public let capability: String
    /// Routing policy applied.
    public let policy: String
    /// Ordered candidates (highest priority first).
    public let candidates: [RuntimeCandidatePlan]
    /// Fallback candidates if primary candidates fail.
    public let fallbackCandidates: [RuntimeCandidatePlan]
    /// How long this plan is valid, in seconds (default: 7 days).
    public let planTtlSeconds: Int
    /// Whether SDK fallback is allowed for this request.
    public let fallbackAllowed: Bool
    /// ISO 8601 timestamp of when the server generated this plan.
    public let serverGeneratedAt: String

    enum CodingKeys: String, CodingKey {
        case model
        case capability
        case policy
        case candidates
        case fallbackCandidates = "fallback_candidates"
        case planTtlSeconds = "plan_ttl_seconds"
        case fallbackAllowed = "fallback_allowed"
        case serverGeneratedAt = "server_generated_at"
    }

    public init(
        model: String,
        capability: String,
        policy: String,
        candidates: [RuntimeCandidatePlan],
        fallbackCandidates: [RuntimeCandidatePlan] = [],
        planTtlSeconds: Int = 604_800,
        fallbackAllowed: Bool = true,
        serverGeneratedAt: String = ""
    ) {
        self.model = model
        self.capability = capability
        self.policy = policy
        self.candidates = candidates
        self.fallbackCandidates = fallbackCandidates
        self.planTtlSeconds = planTtlSeconds
        self.fallbackAllowed = fallbackAllowed
        self.serverGeneratedAt = serverGeneratedAt
    }
}

// MARK: - RuntimeSelection

/// Final resolved runtime selection from the planner.
public struct RuntimeSelection: Sendable, Equatable {
    /// Where inference should run.
    public let locality: RuntimeLocality
    /// Selected engine, if local.
    public let engine: String?
    /// Recommended artifact, if any.
    public let artifact: RuntimeArtifactPlan?
    /// Whether a benchmark was run to produce this selection.
    public let benchmarkRan: Bool
    /// How the selection was determined: "cache", "server_plan", "local_default", "fallback".
    public let source: String
    /// Fallback candidates if this selection fails at runtime.
    public let fallbackCandidates: [RuntimeCandidatePlan]
    /// Human-readable reason for this selection.
    public let reason: String

    public init(
        locality: RuntimeLocality,
        engine: String? = nil,
        artifact: RuntimeArtifactPlan? = nil,
        benchmarkRan: Bool = false,
        source: String = "",
        fallbackCandidates: [RuntimeCandidatePlan] = [],
        reason: String = ""
    ) {
        self.locality = locality
        self.engine = engine
        self.artifact = artifact
        self.benchmarkRan = benchmarkRan
        self.source = source
        self.fallbackCandidates = fallbackCandidates
        self.reason = reason
    }
}

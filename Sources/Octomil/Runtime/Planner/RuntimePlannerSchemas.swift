import Foundation

// MARK: - RuntimeRoutingPolicy

/// Canonical routing policy names shared across all SDKs.
///
/// These string values are the wire-format identifiers sent to the server
/// planner API and used in plan caching. They must match across the Python,
/// Node, iOS, Android, and Browser SDKs.
///
/// **Note:** `quality_first` is intentionally absent. The server does not
/// support it and it must not appear in any SDK.
public enum RuntimeRoutingPolicy {
    /// No data leaves the device. Server plan fetch and telemetry are skipped.
    public static let `private` = "private"
    /// Alias for ``private``. Older SDKs used this name.
    public static let localOnly = "local_only"
    /// Prefer on-device inference, fall back to cloud if unavailable.
    public static let localFirst = "local_first"
    /// Prefer cloud inference, fall back to on-device if unavailable.
    public static let cloudFirst = "cloud_first"
    /// Always use cloud inference. Local engines are never attempted.
    public static let cloudOnly = "cloud_only"
    /// Select the engine with the best performance metrics.
    public static let performanceFirst = "performance_first"

    /// All valid policy names. Use this set for validation.
    public static let allPolicies: Set<String> = [
        `private`, localOnly, localFirst, cloudFirst, cloudOnly, performanceFirst,
    ]
}

// MARK: - RuntimePlanRequest

/// Typed request body for `POST /api/v2/runtime/plan`.
///
/// Mirrors the server contract `RuntimePlanRequest` schema. Using a typed
/// struct instead of a raw dictionary ensures compile-time safety and
/// consistent wire format across SDK versions.
public struct RuntimePlanRequest: Codable, Sendable, Equatable {
    /// Model identifier (e.g. "gemma-2b", "llama-8b").
    public let model: String
    /// Capability needed (e.g. "text", "embeddings", "audio").
    public let capability: String
    /// Routing policy (e.g. "local_first", "cloud_only", "private").
    public let routingPolicy: String?
    /// Device runtime profile.
    public let device: DeviceRuntimeProfile
    /// Whether cloud fallback is permitted.
    public let allowCloudFallback: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case capability
        case routingPolicy = "routing_policy"
        case device
        case allowCloudFallback = "allow_cloud_fallback"
    }

    public init(
        model: String,
        capability: String,
        routingPolicy: String? = nil,
        device: DeviceRuntimeProfile,
        allowCloudFallback: Bool? = nil
    ) {
        self.model = model
        self.capability = capability
        self.routingPolicy = routingPolicy
        self.device = device
        self.allowCloudFallback = allowCloudFallback
    }
}

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        locality = try container.decode(RuntimeLocality.self, forKey: .locality)
        priority = try container.decode(Int.self, forKey: .priority)
        confidence = try container.decode(Double.self, forKey: .confidence)
        reason = try container.decode(String.self, forKey: .reason)
        engine = try container.decodeIfPresent(String.self, forKey: .engine).map(RuntimeEngineID.canonical)
        engineVersionConstraint = try container.decodeIfPresent(
            String.self,
            forKey: .engineVersionConstraint
        )
        artifact = try container.decodeIfPresent(RuntimeArtifactPlan.self, forKey: .artifact)
        benchmarkRequired = try container.decodeIfPresent(Bool.self, forKey: .benchmarkRequired) ?? false
        gates = try container.decodeIfPresent([CandidateGate].self, forKey: .gates) ?? []
    }
}

// MARK: - RuntimeLocality

/// Where inference runs: on-device or in the cloud.
public enum RuntimeLocality: String, Codable, Sendable, Equatable {
    case local
    case cloud
}

// MARK: - AppResolution

/// Server-resolved application context for `@app/{slug}/{capability}` model refs.
public struct AppResolution: Codable, Sendable, Equatable {
    public let appId: String
    public let appSlug: String?
    public let capability: String
    public let routingPolicy: String
    public let selectedModel: String
    public let selectedModelVariantId: String?
    public let selectedModelVersion: String?
    public let artifactCandidates: [RuntimeArtifactPlan]
    public let preferredEngines: [String]
    public let fallbackPolicy: String?
    public let planTtlSeconds: Int

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case appSlug = "app_slug"
        case capability
        case routingPolicy = "routing_policy"
        case selectedModel = "selected_model"
        case selectedModelVariantId = "selected_model_variant_id"
        case selectedModelVersion = "selected_model_version"
        case artifactCandidates = "artifact_candidates"
        case preferredEngines = "preferred_engines"
        case fallbackPolicy = "fallback_policy"
        case planTtlSeconds = "plan_ttl_seconds"
    }

    public init(
        appId: String,
        appSlug: String? = nil,
        capability: String,
        routingPolicy: String,
        selectedModel: String,
        selectedModelVariantId: String? = nil,
        selectedModelVersion: String? = nil,
        artifactCandidates: [RuntimeArtifactPlan] = [],
        preferredEngines: [String] = [],
        fallbackPolicy: String? = nil,
        planTtlSeconds: Int = 604_800
    ) {
        self.appId = appId
        self.appSlug = appSlug
        self.capability = capability
        self.routingPolicy = routingPolicy
        self.selectedModel = selectedModel
        self.selectedModelVariantId = selectedModelVariantId
        self.selectedModelVersion = selectedModelVersion
        self.artifactCandidates = artifactCandidates
        self.preferredEngines = preferredEngines
        self.fallbackPolicy = fallbackPolicy
        self.planTtlSeconds = planTtlSeconds
    }
}

// MARK: - ModelResolution

/// Generalized resolution metadata for non-app model ref types.
///
/// Returned by the server when the model ref resolves through a deployment,
/// experiment, capability default, or plain model lookup. Carries the
/// deployment_id, experiment_id, and variant_id needed for SDK route
/// telemetry correlation.
public struct ModelResolution: Codable, Sendable, Equatable {
    /// How the ref was classified (e.g. "deployment", "experiment", "model").
    public let refKind: String
    /// The original model ref string as provided by the caller.
    public let originalRef: String
    /// The resolved model identifier.
    public let resolvedModel: String
    /// Deployment ID when the ref resolved through a deployment.
    public let deploymentId: String?
    /// Deployment key when the ref resolved through a deployment.
    public let deploymentKey: String?
    /// Experiment ID when the ref resolved through an experiment.
    public let experimentId: String?
    /// Variant ID when a specific variant was selected.
    public let variantId: String?
    /// Variant name when a specific variant was selected.
    public let variantName: String?
    /// Capability the ref resolved for.
    public let capability: String?
    /// Routing policy applied by the server during resolution.
    public let routingPolicy: String?

    enum CodingKeys: String, CodingKey {
        case refKind = "ref_kind"
        case originalRef = "original_ref"
        case resolvedModel = "resolved_model"
        case deploymentId = "deployment_id"
        case deploymentKey = "deployment_key"
        case experimentId = "experiment_id"
        case variantId = "variant_id"
        case variantName = "variant_name"
        case capability
        case routingPolicy = "routing_policy"
    }

    public init(
        refKind: String,
        originalRef: String,
        resolvedModel: String,
        deploymentId: String? = nil,
        deploymentKey: String? = nil,
        experimentId: String? = nil,
        variantId: String? = nil,
        variantName: String? = nil,
        capability: String? = nil,
        routingPolicy: String? = nil
    ) {
        self.refKind = refKind
        self.originalRef = originalRef
        self.resolvedModel = resolvedModel
        self.deploymentId = deploymentId
        self.deploymentKey = deploymentKey
        self.experimentId = experimentId
        self.variantId = variantId
        self.variantName = variantName
        self.capability = capability
        self.routingPolicy = routingPolicy
    }
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
    /// App resolution details when the request used an app ref.
    public let appResolution: AppResolution?
    /// Resolution metadata for deployment/experiment/capability/model refs.
    public let resolution: ModelResolution?

    enum CodingKeys: String, CodingKey {
        case model
        case capability
        case policy
        case candidates
        case fallbackCandidates = "fallback_candidates"
        case planTtlSeconds = "plan_ttl_seconds"
        case fallbackAllowed = "fallback_allowed"
        case serverGeneratedAt = "server_generated_at"
        case appResolution = "app_resolution"
        case resolution
    }

    public init(
        model: String,
        capability: String,
        policy: String,
        candidates: [RuntimeCandidatePlan],
        fallbackCandidates: [RuntimeCandidatePlan] = [],
        planTtlSeconds: Int = 604_800,
        fallbackAllowed: Bool = true,
        serverGeneratedAt: String = "",
        appResolution: AppResolution? = nil,
        resolution: ModelResolution? = nil
    ) {
        self.model = model
        self.capability = capability
        self.policy = policy
        self.candidates = candidates
        self.fallbackCandidates = fallbackCandidates
        self.planTtlSeconds = planTtlSeconds
        self.fallbackAllowed = fallbackAllowed
        self.serverGeneratedAt = serverGeneratedAt
        self.appResolution = appResolution
        self.resolution = resolution
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
    /// How the selection was determined — internal value; normalized via ``PlannerSourceNormalizer``.
    public let source: String
    /// Fallback candidates if this selection fails at runtime.
    public let fallbackCandidates: [RuntimeCandidatePlan]
    /// Human-readable reason for this selection.
    public let reason: String
    /// Model identifier used in the request (e.g. "gemma-2b").
    public let model: String
    /// Capability used in the request (e.g. "text", "embeddings").
    public let capability: String

    public init(
        locality: RuntimeLocality,
        engine: String? = nil,
        artifact: RuntimeArtifactPlan? = nil,
        benchmarkRan: Bool = false,
        source: String = "",
        fallbackCandidates: [RuntimeCandidatePlan] = [],
        reason: String = "",
        model: String = "",
        capability: String = ""
    ) {
        self.locality = locality
        self.engine = engine
        self.artifact = artifact
        self.benchmarkRan = benchmarkRan
        self.source = source
        self.fallbackCandidates = fallbackCandidates
        self.reason = reason
        self.model = model
        self.capability = capability
    }

    /// Build a ``PlannerRouteMetadata`` summary from this selection.
    ///
    /// Maps the internal selection state to the canonical contract-backed
    /// nested ``PlannerRouteMetadata`` shape shared across all SDKs.
    ///
    /// The contract allows only three planner source values:
    /// - `"server"` — live plan from the server planner API
    /// - `"cache"` — cached plan reused within TTL
    /// - `"offline"` — synthetic plan when server is unreachable
    ///
    /// Internal source strings are normalized as follows:
    /// - `"server_plan"` → `"server"`
    /// - `"cache"` → `"cache"`
    /// - `"local_default"`, `"fallback"`, `"empty"`, `""` → `"offline"`
    public func routeMetadata() -> PlannerRouteMetadata {
        let isFallback = source == "fallback" || reason.hasPrefix("fallback")
        let localityString = locality == .local ? "local" : "cloud"
        let modeString = locality == .local ? "sdk_runtime" : "hosted_gateway"

        // Normalize internal source to contract enum: server | cache | offline
        let plannerSourceString: String
        switch source {
        case "server_plan":
            plannerSourceString = "server"
        case "cache":
            plannerSourceString = "cache"
        default:
            // local_default, fallback, empty, or any unknown value → offline
            plannerSourceString = "offline"
        }

        let execution = RouteExecution(
            locality: localityString,
            mode: modeString,
            engine: engine
        )

        let requested = RouteModelRequested(
            ref: model,
            kind: model.isEmpty ? "unknown" : "model",
            capability: capability.isEmpty ? nil : capability
        )
        let routeModel = RouteModel(requested: requested, resolved: nil)

        var routeArtifact: RouteArtifact?
        if let artifact {
            let cacheStatus: String
            if source == "cache" {
                cacheStatus = "hit"
            } else if artifact.uri != nil {
                cacheStatus = "miss"
            } else {
                cacheStatus = "not_applicable"
            }
            routeArtifact = RouteArtifact(
                id: artifact.artifactId,
                version: artifact.modelVersion,
                format: artifact.format,
                digest: artifact.digest,
                cache: ArtifactCache(status: cacheStatus, managedBy: "octomil")
            )
        }

        let plannerInfo = PlannerInfo(source: plannerSourceString)
        let fallbackInfo = FallbackInfo(used: isFallback)

        let reasonCode: String
        switch source {
        case "server_plan": reasonCode = "server_plan"
        case "cache": reasonCode = "cached_plan"
        case "local_default": reasonCode = "local_default"
        case "fallback": reasonCode = "fallback"
        default: reasonCode = source.isEmpty ? "offline" : source
        }

        let routeReason = RouteReason(code: reasonCode, message: reason)

        return PlannerRouteMetadata(
            status: "selected",
            execution: execution,
            model: routeModel,
            artifact: routeArtifact,
            planner: plannerInfo,
            fallback: fallbackInfo,
            reason: routeReason
        )
    }
}

// MARK: - PlannerRouteMetadata (Contract-Backed Nested Shape)

/// Execution details for a route decision.
public struct RouteExecution: Sendable, Equatable {
    /// Where inference runs: "local" or "cloud". Never "on_device".
    public let locality: String
    /// Execution mode: "sdk_runtime" (local), "hosted_gateway" (cloud), "external_endpoint".
    public let mode: String
    /// Engine used, if any (e.g. "mlx-lm", "llama.cpp").
    public let engine: String?

    public init(locality: String, mode: String, engine: String? = nil) {
        self.locality = locality
        self.mode = mode
        self.engine = engine
    }
}

/// The model reference as requested by the caller.
public struct RouteModelRequested: Sendable, Equatable {
    /// Model reference string (e.g. "gemma-2b").
    public let ref: String
    /// Kind of reference: "model", "app", "deployment", "alias", "default", "unknown".
    public let kind: String
    /// Capability requested, if any (e.g. "text", "embeddings").
    public let capability: String?

    public init(ref: String, kind: String = "unknown", capability: String? = nil) {
        self.ref = ref
        self.kind = kind
        self.capability = capability
    }
}

/// Resolved model identity after planner resolution.
public struct RouteModelResolved: Sendable, Equatable {
    public let id: String?
    public let slug: String?
    public let versionId: String?
    public let variantId: String?

    public init(id: String? = nil, slug: String? = nil, versionId: String? = nil, variantId: String? = nil) {
        self.id = id
        self.slug = slug
        self.versionId = versionId
        self.variantId = variantId
    }
}

/// Model information: what was requested and what was resolved.
public struct RouteModel: Sendable, Equatable {
    public let requested: RouteModelRequested
    public let resolved: RouteModelResolved?

    public init(requested: RouteModelRequested, resolved: RouteModelResolved? = nil) {
        self.requested = requested
        self.resolved = resolved
    }
}

/// Cache status for a model artifact.
public struct ArtifactCache: Sendable, Equatable {
    /// Cache status: "hit", "miss", "downloaded", "not_applicable", "unavailable".
    public let status: String
    /// Who manages the cache: "octomil", "runtime", "external".
    public let managedBy: String?

    public init(status: String = "not_applicable", managedBy: String? = nil) {
        self.status = status
        self.managedBy = managedBy
    }
}

/// Artifact metadata for the route decision.
public struct RouteArtifact: Sendable, Equatable {
    public let id: String?
    public let version: String?
    public let format: String?
    public let digest: String?
    public let cache: ArtifactCache

    public init(
        id: String? = nil,
        version: String? = nil,
        format: String? = nil,
        digest: String? = nil,
        cache: ArtifactCache = ArtifactCache()
    ) {
        self.id = id
        self.version = version
        self.format = format
        self.digest = digest
        self.cache = cache
    }
}

/// How the routing plan was obtained.
public struct PlannerInfo: Sendable, Equatable {
    /// Plan source: "server", "cache", "offline".
    public let source: String

    public init(source: String = "offline") {
        self.source = source
    }
}

/// Whether a fallback route was used.
public struct FallbackInfo: Sendable, Equatable {
    public let used: Bool

    public init(used: Bool = false) {
        self.used = used
    }
}

/// Machine-readable reason code and human-readable message.
public struct RouteReason: Sendable, Equatable {
    public let code: String
    public let message: String

    public init(code: String = "", message: String = "") {
        self.code = code
        self.message = message
    }
}

/// Contract-backed route metadata shared across all SDKs.
///
/// Provides a uniform, nested summary of how a particular inference
/// request was routed. Matches the canonical contract shape defined
/// in `octomil-contracts`.
///
/// **Important:** Public locality values are "local" or "cloud".
/// The value "on_device" must never appear. Telemetry adapters may
/// map "local" to "on_device" internally if needed.
public struct PlannerRouteMetadata: Sendable, Equatable {
    /// Route status: "selected" or "unavailable".
    public let status: String
    /// Execution details (locality, mode, engine).
    public let execution: RouteExecution?
    /// Model requested and resolved.
    public let model: RouteModel
    /// Artifact details, if any.
    public let artifact: RouteArtifact?
    /// How the plan was obtained.
    public let planner: PlannerInfo
    /// Whether a fallback was used.
    public let fallback: FallbackInfo
    /// Reason code and message for this routing decision.
    public let reason: RouteReason

    public init(
        status: String = "selected",
        execution: RouteExecution? = nil,
        model: RouteModel,
        artifact: RouteArtifact? = nil,
        planner: PlannerInfo = PlannerInfo(),
        fallback: FallbackInfo = FallbackInfo(),
        reason: RouteReason = RouteReason()
    ) {
        self.status = status
        self.execution = execution
        self.model = model
        self.artifact = artifact
        self.planner = planner
        self.fallback = fallback
        self.reason = reason
    }
}

// MARK: - PlannerSourceNormalizer

/// Normalizes planner source strings to the canonical contract enum.
///
/// Canonical values: `"server"`, `"cache"`, `"offline"`.
///
/// Aliases:
/// - `"server_plan"` -> `"server"`
/// - `"cached"` -> `"cache"`
/// - `"local_default"`, `"fallback"`, `"none"`, `"local_benchmark"`, `""` -> `"offline"`
///
/// Unknown values collapse to `"offline"` so SDK output boundaries never emit
/// a contract-invalid planner source.
public enum PlannerSourceNormalizer {
    /// Canonical planner source values.
    public static let canonicalSources: Set<String> = ["server", "cache", "offline"]

    private static let aliases: [String: String] = [
        "local_default": "offline",
        "server_plan": "server",
        "cached": "cache",
        "fallback": "offline",
        "none": "offline",
        "local_benchmark": "offline",
    ]

    /// Normalize a planner source string to its canonical value.
    public static func normalize(_ source: String) -> String {
        if source.isEmpty { return "offline" }
        if canonicalSources.contains(source) { return source }
        return aliases[source] ?? "offline"
    }
}

// MARK: - RuntimeBenchmarkSubmission

/// Privacy-safe benchmark submission for `POST /api/v2/runtime/benchmarks`.
///
/// This struct enforces that no prompts, user inputs, file paths, or other
/// personally identifying information is included in benchmark telemetry.
/// Only hardware/engine performance metrics are submitted.
public struct RuntimeBenchmarkSubmission: Sendable, Equatable {
    /// Model identifier.
    public let model: String
    /// Capability string (e.g. "text", "embeddings", "audio_transcription").
    public let capability: String
    /// Engine name (e.g. "mlx-lm", "llama.cpp", "coreml").
    public let engine: String
    /// Whether the benchmark completed successfully.
    public let success: Bool
    /// Tokens per second achieved (0 for non-token modalities).
    public let tokensPerSecond: Double
    /// Time to first token/chunk in milliseconds.
    public let ttftMs: Double
    /// Peak memory usage in bytes.
    public let peakMemoryBytes: Int64
    /// Additional privacy-safe metadata. Validated against ``bannedKeys``.
    public let metadata: [String: String]

    /// Keys that must NEVER appear in benchmark metadata.
    ///
    /// These keys could leak user data (prompts, file paths, personally
    /// identifying information) and violate the privacy contract.
    public static let bannedKeys: Set<String> = [
        "prompt", "input", "output", "response", "file", "file_path",
        "path", "user", "user_id", "email", "ip", "ip_address",
        "token", "api_key", "secret", "password", "content",
    ]

    public init(
        model: String,
        capability: String,
        engine: String,
        success: Bool = true,
        tokensPerSecond: Double = 0.0,
        ttftMs: Double = 0.0,
        peakMemoryBytes: Int64 = 0,
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.capability = capability
        self.engine = RuntimeEngineID.canonical(engine)
        self.success = success
        self.tokensPerSecond = tokensPerSecond
        self.ttftMs = ttftMs
        self.peakMemoryBytes = peakMemoryBytes
        // Strip any banned keys from metadata
        self.metadata = metadata.filter { !Self.bannedKeys.contains($0.key.lowercased()) }
    }

    /// Validate that no banned keys are present in a metadata dictionary.
    ///
    /// - Parameter metadata: The metadata to validate.
    /// - Returns: Set of banned key names found, empty if valid.
    public static func validateMetadata(_ metadata: [String: String]) -> Set<String> {
        let lowered = Set(metadata.keys.map { $0.lowercased() })
        return lowered.intersection(bannedKeys)
    }

    /// Convert to a dictionary suitable for JSON serialization and upload.
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "source": "planner",
            "model": model,
            "capability": capability,
            "engine": engine,
            "success": success,
            "tokens_per_second": tokensPerSecond,
            "ttft_ms": ttftMs,
            "peak_memory_bytes": peakMemoryBytes,
        ]
        if !metadata.isEmpty {
            dict["metadata"] = metadata
        }
        return dict
    }
}

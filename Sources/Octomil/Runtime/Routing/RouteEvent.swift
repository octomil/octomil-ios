import Foundation

// MARK: - Route Event

/// Structured route event emitted after each inference request completes.
///
/// Contains routing metadata suitable for telemetry upload. NEVER includes
/// user content (prompt, input, output, audio, file paths, etc.).
///
/// All cross-SDK canonical correlation fields are present:
/// - `routeId`, `requestId` — unique identifiers for correlation
/// - `appSlug`, `deploymentId`, `experimentId`, `variantId` — deployment context
/// - `selectedLocality`, `finalMode` — where and how inference ran
/// - `fallbackUsed`, `fallbackTriggerCode`, `fallbackTriggerStage` — fallback info
/// - `candidateAttempts` — how many candidates were evaluated
public struct RouteEvent: Codable, Sendable, Equatable {
    /// Unique route identifier (generated per routing decision).
    public let routeId: String
    /// Unique request identifier for correlation.
    public let requestId: String
    /// Planner plan ID (if a server plan was used).
    public let planId: String?
    /// Capability surface being routed (chat, embeddings, audio, responses).
    public let capability: String
    /// Routing policy applied (auto, local_only, cloud_only, private).
    public let policy: String?
    /// Source of the routing plan (server, local_default, cached).
    public let plannerSource: String?
    /// The locality where inference was ultimately executed.
    public let selectedLocality: String
    /// Backward-compatible route metadata locality alias.
    public let finalLocality: String
    /// The execution mode used (sdk_runtime, hosted_gateway, external_endpoint).
    public let finalMode: String
    /// Engine used for inference (e.g. coreml, llamacpp, cloud).
    public let engine: String?
    /// Whether fallback was triggered during routing.
    public let fallbackUsed: Bool
    /// The code that triggered fallback (if applicable).
    public let fallbackTriggerCode: String?
    /// The stage at which fallback was triggered (prepare, verify, gate, inference).
    public let fallbackTriggerStage: String?
    /// Number of candidates evaluated during routing.
    public let candidateAttempts: Int
    /// Model reference string as provided by the caller.
    public let modelRef: String?
    /// Kind of model reference: model|app|capability|deployment|experiment|alias|default|unknown.
    public let modelRefKind: String?
    /// App slug for @app references.
    public let appSlug: String?
    /// App ID for @app references.
    public let appId: String?
    /// Deployment ID for correlation.
    public let deploymentId: String?
    /// Experiment ID for correlation.
    public let experimentId: String?
    /// Variant ID for experiment/deployment variants.
    public let variantId: String?
    /// Artifact ID of the model artifact used.
    public let artifactId: String?
    /// Cache status for the route decision: "hit", "miss", or "not_applicable".
    public let cacheStatus: String?

    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
        case requestId = "request_id"
        case planId = "plan_id"
        case capability
        case policy
        case plannerSource = "planner_source"
        case finalLocality = "final_locality"
        case selectedLocality = "selected_locality"
        case finalMode = "final_mode"
        case engine
        case fallbackUsed = "fallback_used"
        case fallbackTriggerCode = "fallback_trigger_code"
        case fallbackTriggerStage = "fallback_trigger_stage"
        case candidateAttempts = "candidate_attempts"
        case modelRef = "model_ref"
        case modelRefKind = "model_ref_kind"
        case appSlug = "app_slug"
        case appId = "app_id"
        case deploymentId = "deployment_id"
        case experimentId = "experiment_id"
        case variantId = "variant_id"
        case artifactId = "artifact_id"
        case cacheStatus = "cache_status"
    }

    public init(
        routeId: String = RouteEvent.generateRouteId(),
        requestId: String,
        planId: String? = nil,
        capability: String,
        policy: String? = nil,
        plannerSource: String? = nil,
        selectedLocality: String,
        finalMode: String,
        engine: String? = nil,
        fallbackUsed: Bool = false,
        fallbackTriggerCode: String? = nil,
        fallbackTriggerStage: String? = nil,
        candidateAttempts: Int = 0,
        modelRef: String? = nil,
        modelRefKind: String? = nil,
        appSlug: String? = nil,
        appId: String? = nil,
        deploymentId: String? = nil,
        experimentId: String? = nil,
        variantId: String? = nil,
        artifactId: String? = nil,
        cacheStatus: String? = nil
    ) {
        self.routeId = routeId
        self.requestId = requestId
        self.planId = planId
        self.capability = capability
        self.policy = policy
        self.plannerSource = plannerSource
        self.selectedLocality = selectedLocality
        self.finalLocality = selectedLocality
        self.finalMode = finalMode
        self.engine = engine
        self.fallbackUsed = fallbackUsed
        self.fallbackTriggerCode = fallbackTriggerCode
        self.fallbackTriggerStage = fallbackTriggerStage
        self.candidateAttempts = candidateAttempts
        self.modelRef = modelRef
        self.modelRefKind = modelRefKind
        self.appSlug = appSlug
        self.appId = appId
        self.deploymentId = deploymentId
        self.experimentId = experimentId
        self.variantId = variantId
        self.artifactId = artifactId
        self.cacheStatus = cacheStatus
    }

    /// Backward-compatible initializer for the earlier production-routing surface.
    public init(
        routeId: String,
        requestId: String,
        planId: String? = nil,
        capability: String,
        policy: String? = nil,
        plannerSource: String? = nil,
        finalLocality: String,
        engine: String? = nil,
        fallbackUsed: Bool = false,
        fallbackTriggerCode: String? = nil,
        candidateAttempts: Int = 0,
        modelRefKind: String = "model"
    ) {
        self.init(
            routeId: routeId,
            requestId: requestId,
            planId: planId,
            capability: capability,
            policy: policy,
            plannerSource: plannerSource,
            selectedLocality: finalLocality,
            finalMode: finalLocality == "cloud" ? "hosted_gateway" : "sdk_runtime",
            engine: engine,
            fallbackUsed: fallbackUsed,
            fallbackTriggerCode: fallbackTriggerCode,
            fallbackTriggerStage: nil,
            candidateAttempts: candidateAttempts,
            modelRefKind: modelRefKind
        )
    }

    /// Build a RouteEvent from a routing decision and request ID.
    public static func from(
        decision: RoutingDecisionResult,
        requestId: String,
        capability: String
    ) -> RouteEvent {
        RouteEvent(
            routeId: decision.routeMetadata.routeId,
            requestId: requestId,
            planId: decision.routeMetadata.planId,
            capability: capability,
            policy: decision.routeMetadata.policy,
            plannerSource: decision.routeMetadata.plannerSource,
            selectedLocality: decision.routeMetadata.finalLocality,
            finalMode: decision.mode,
            engine: decision.routeMetadata.engine,
            fallbackUsed: decision.routeMetadata.fallbackUsed,
            fallbackTriggerCode: decision.routeMetadata.fallbackTriggerCode,
            fallbackTriggerStage: nil,
            candidateAttempts: decision.routeMetadata.candidateAttempts,
            modelRefKind: decision.routeMetadata.modelRefKind
        )
    }

    /// Generate a unique route ID.
    public static func generateRouteId() -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let random = String(Int.random(in: 0..<Int(1e10)), radix: 36)
        return "route_\(timestamp)\(random)"
    }
}

// MARK: - Forbidden Telemetry Keys

/// Keys that must NEVER appear in a RouteEvent or any telemetry payload.
///
/// Prevents prompt/input/output/audio/file_path leakage into telemetry.
/// Cross-SDK canonical constant.
public let forbiddenTelemetryKeys: Set<String> = [
    "prompt",
    "input",
    "output",
    "completion",
    "audio",
    "audio_bytes",
    "file_path",
    "text",
    "content",
    "messages",
    "system_prompt",
    "documents",
    "image",
    "image_url",
    "embedding",
    "embeddings",
]

// MARK: - Validation & Stripping

/// Validates that a dictionary does not contain any forbidden telemetry keys.
///
/// - Parameter attributes: Key-value map to validate.
/// - Throws: `RouteEventValidationError.forbiddenKeyPresent` if a forbidden key is found.
public func validateRouteEventAttributes(_ attributes: [String: Any]) throws {
    if let first = findForbiddenTelemetryKeys(attributes).first {
        throw RouteEventValidationError.forbiddenKeyPresent(first)
    }
}

/// Strips any forbidden telemetry keys from a nested dictionary.
///
/// Returns a new dictionary with forbidden keys removed at any depth.
/// Use before uploading custom metadata alongside route events.
public func stripForbiddenKeys(_ attributes: [String: Any]) -> [String: Any] {
    scrubForbiddenTelemetryValue(attributes) as? [String: Any] ?? [:]
}

/// Strips forbidden keys from a `TelemetryValue` attribute map.
///
/// Convenience overload for the telemetry pipeline.
public func stripForbiddenTelemetryKeys(_ attributes: [String: TelemetryValue]) -> [String: TelemetryValue] {
    scrubForbiddenTelemetryValue(attributes) as? [String: TelemetryValue] ?? [:]
}

/// Errors raised during route event validation.
public enum RouteEventValidationError: Error, LocalizedError {
    case forbiddenKeyPresent(String)

    public var errorDescription: String? {
        switch self {
        case .forbiddenKeyPresent(let key):
            return "RouteEvent contains forbidden telemetry key: \"\(key)\". Route events must never include user content."
        }
    }
}

private func findForbiddenTelemetryKeys(_ value: Any, path: String = "") -> [String] {
    if let array = value as? [Any] {
        return array.enumerated().flatMap { index, item in
            findForbiddenTelemetryKeys(item, path: "\(path)[\(index)]")
        }
    }
    guard let dictionary = value as? [String: Any] else {
        return []
    }

    var violations: [String] = []
    for (key, child) in dictionary {
        let fullPath = path.isEmpty ? key : "\(path).\(key)"
        if forbiddenTelemetryKeys.contains(key) {
            violations.append(fullPath)
            continue
        }
        violations.append(contentsOf: findForbiddenTelemetryKeys(child, path: fullPath))
    }
    return violations
}

private func scrubForbiddenTelemetryValue(_ value: Any) -> Any {
    if let array = value as? [Any] {
        return array.map(scrubForbiddenTelemetryValue)
    }
    guard let dictionary = value as? [String: Any] else {
        return value
    }

    var scrubbed: [String: Any] = [:]
    for (key, child) in dictionary {
        if forbiddenTelemetryKeys.contains(key) {
            continue
        }
        scrubbed[key] = scrubForbiddenTelemetryValue(child)
    }
    return scrubbed
}

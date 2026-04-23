import Foundation
import os.log

// MARK: - Model Reference Parsing

/// Parsed model reference from a user-provided model string.
///
/// The SDK recognises several reference formats but does NOT resolve them
/// locally — the server planner does. The SDK records the ref kind in
/// route metadata so telemetry can group by resolution strategy.
///
/// Supported formats:
/// - `@app/<slug>/<capability>` — app-scoped capability
/// - `@capability/<cap>` — global capability
/// - `deploy_<id>` — deployment ID
/// - `exp_<id>/<variant>` — experiment variant ref
/// - `alias:<name>` — model alias
/// - anything else — plain model ID (passed through to the runtime)
public struct ParsedModelRef: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case model
        case app
        case capability
        case deployment
        case experiment
        case alias
        case `default`
        case unknown
    }

    public let kind: Kind
    public let raw: String
    public let modelSlug: String?
    public let appSlug: String?
    public let capability: String?
    public let deploymentId: String?
    public let experimentId: String?
    public let variantId: String?

    public init(
        kind: Kind,
        raw: String,
        modelSlug: String? = nil,
        appSlug: String? = nil,
        capability: String? = nil,
        deploymentId: String? = nil,
        experimentId: String? = nil,
        variantId: String? = nil
    ) {
        self.kind = kind
        self.raw = raw
        self.modelSlug = modelSlug
        self.appSlug = appSlug
        self.capability = capability
        self.deploymentId = deploymentId
        self.experimentId = experimentId
        self.variantId = variantId
    }

    /// Parse a model string into a typed reference.
    public static func parse(_ model: String) -> ParsedModelRef {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return ParsedModelRef(kind: .default, raw: trimmed)
        }
        if trimmed.hasPrefix("@app/") {
            let parts = trimmed.dropFirst("@app/".count).split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                return ParsedModelRef(kind: .app, raw: trimmed, appSlug: parts[0], capability: parts[1])
            }
            return ParsedModelRef(kind: .unknown, raw: trimmed)
        }
        if trimmed.hasPrefix("@capability/") {
            let cap = String(trimmed.dropFirst("@capability/".count))
            return cap.isEmpty
                ? ParsedModelRef(kind: .unknown, raw: trimmed)
                : ParsedModelRef(kind: .capability, raw: trimmed, capability: cap)
        }
        if trimmed.hasPrefix("deploy_") {
            if trimmed.count > "deploy_".count {
                return ParsedModelRef(kind: .deployment, raw: trimmed, deploymentId: trimmed)
            }
            return ParsedModelRef(kind: .unknown, raw: trimmed)
        }
        if trimmed.hasPrefix("exp_"), let slash = trimmed.firstIndex(of: "/") {
            let experimentId = String(trimmed[..<slash])
            let variantId = String(trimmed[trimmed.index(after: slash)...])
            if !experimentId.isEmpty, !variantId.isEmpty {
                return ParsedModelRef(kind: .experiment, raw: trimmed, experimentId: experimentId, variantId: variantId)
            }
            return ParsedModelRef(kind: .unknown, raw: trimmed)
        }
        if trimmed.hasPrefix("alias:") {
            if trimmed.count > "alias:".count {
                return ParsedModelRef(kind: .alias, raw: trimmed)
            }
            return ParsedModelRef(kind: .unknown, raw: trimmed)
        }
        if trimmed.hasPrefix("@") || trimmed.contains("://") {
            return ParsedModelRef(kind: .unknown, raw: trimmed)
        }
        return ParsedModelRef(kind: .model, raw: trimmed, modelSlug: trimmed)
    }
}

// MARK: - RequestRoutingContext

/// All inputs needed to resolve a routing decision for a single request.
public struct RequestRoutingContext: Sendable {
    /// Model identifier or reference string.
    public let model: String
    /// Capability being requested: "chat", "embeddings", "audio", "text".
    public let capability: String
    /// Whether the caller wants streaming output.
    public let streaming: Bool
    /// Cached plan from the planner store, if available.
    public let cachedPlan: RuntimePlanResponse?
    /// Per-request routing policy override.
    public let routingPolicy: AppRoutingPolicy?

    public init(
        model: String,
        capability: String = "chat",
        streaming: Bool = false,
        cachedPlan: RuntimePlanResponse? = nil,
        routingPolicy: AppRoutingPolicy? = nil
    ) {
        self.model = model
        self.capability = capability
        self.streaming = streaming
        self.cachedPlan = cachedPlan
        self.routingPolicy = routingPolicy
    }
}

// MARK: - CanonicalRouteMetadata typealias

/// The canonical route metadata shape, as defined in octomil-contracts.
///
/// This is the ``PlannerRouteMetadata`` type from ``RuntimePlannerSchemas``,
/// re-aliased for cross-SDK naming consistency. Prefer this over the flat
/// ``RouteMetadata`` for new code.
public typealias CanonicalRouteMetadata = PlannerRouteMetadata

// MARK: - RouteMetadata

/// Privacy-safe metadata attached to every routed request.
///
/// NEVER contains: prompt, input, output, audio, filePath, content, messages.
/// Only operational metadata for routing telemetry and debugging.
///
/// - Important: This flat shape is **deprecated**. Prefer ``CanonicalRouteMetadata``
///   (the contract-backed nested shape) via ``RoutingDecisionResult/canonicalMetadata``.
@available(*, deprecated, message: "Use CanonicalRouteMetadata (PlannerRouteMetadata) instead")
public struct RouteMetadata: Sendable, Equatable {
    /// Unique ID for this routing decision.
    public let routeId: String
    /// The plan ID from the server planner, if a plan was used.
    public let planId: String?
    /// How the plan was obtained — canonical: "server", "cache", "offline".
    public let plannerSource: String
    /// The routing policy that was applied.
    public let policy: String?
    /// Final locality where inference ran.
    public let finalLocality: String
    /// Engine used for inference.
    public let engine: String?
    /// The parsed model reference kind.
    public let modelRefKind: String
    /// Model reference string as supplied by the caller.
    public let modelRef: String?
    /// App slug, when the model ref is app-scoped.
    public let appSlug: String?
    /// Deployment ID or key, when the model ref is deployment-scoped.
    public let deploymentId: String?
    /// Experiment ID, when the model ref is experiment-scoped.
    public let experimentId: String?
    /// Variant ID, when the model ref is experiment-scoped.
    public let variantId: String?
    /// Artifact cache status for the selected local attempt.
    public let cacheStatus: String?
    /// Whether fallback was triggered during this request.
    public let fallbackUsed: Bool
    /// Machine-readable code for what triggered the fallback.
    public let fallbackTriggerCode: String?
    /// Number of candidate attempts evaluated.
    public let candidateAttempts: Int

    public init(
        routeId: String = UUID().uuidString,
        planId: String? = nil,
        plannerSource: String = "offline",
        policy: String? = nil,
        finalLocality: String,
        engine: String? = nil,
        modelRefKind: String = "model",
        modelRef: String? = nil,
        appSlug: String? = nil,
        deploymentId: String? = nil,
        experimentId: String? = nil,
        variantId: String? = nil,
        cacheStatus: String? = nil,
        fallbackUsed: Bool = false,
        fallbackTriggerCode: String? = nil,
        candidateAttempts: Int = 0
    ) {
        self.routeId = routeId
        self.planId = planId
        self.plannerSource = plannerSource
        self.policy = policy
        self.finalLocality = finalLocality
        self.engine = engine
        self.modelRefKind = modelRefKind
        self.modelRef = modelRef
        self.appSlug = appSlug
        self.deploymentId = deploymentId
        self.experimentId = experimentId
        self.variantId = variantId
        self.cacheStatus = cacheStatus
        self.fallbackUsed = fallbackUsed
        self.fallbackTriggerCode = fallbackTriggerCode
        self.candidateAttempts = candidateAttempts
    }
}

// MARK: - RoutingDecisionResult

/// The resolved routing decision for a single request.
///
/// Contains enough information for the caller to dispatch inference
/// to the correct runtime and attach route metadata to the response.
public struct RoutingDecisionResult: Sendable {
    /// Where inference should run.
    public let locality: String
    /// Execution mode: "sdk_runtime" or "hosted_gateway".
    public let mode: String
    /// Engine to use, if local.
    public let engine: String?
    /// Privacy-safe route metadata (flat shape).
    /// - Important: Deprecated. Use ``canonicalMetadata`` instead.
    @available(*, deprecated, message: "Use canonicalMetadata instead")
    public let routeMetadata: RouteMetadata
    /// Contract-backed canonical route metadata (nested shape).
    public let canonicalMetadata: CanonicalRouteMetadata
    /// Full attempt loop result for telemetry.
    public let attemptResult: AttemptLoopResult

    @available(*, deprecated, message: "Use init with canonicalMetadata instead")
    public init(
        locality: String,
        mode: String,
        engine: String? = nil,
        routeMetadata: RouteMetadata,
        attemptResult: AttemptLoopResult
    ) {
        self.locality = locality
        self.mode = mode
        self.engine = engine
        self.routeMetadata = routeMetadata
        self.canonicalMetadata = CanonicalRouteMetadata(
            status: "selected",
            model: RouteModel(requested: RouteModelRequested(ref: routeMetadata.modelRef ?? ""))
        )
        self.attemptResult = attemptResult
    }

    public init(
        locality: String,
        mode: String,
        engine: String? = nil,
        routeMetadata: RouteMetadata,
        canonicalMetadata: CanonicalRouteMetadata,
        attemptResult: AttemptLoopResult
    ) {
        self.locality = locality
        self.mode = mode
        self.engine = engine
        self.routeMetadata = routeMetadata
        self.canonicalMetadata = canonicalMetadata
        self.attemptResult = attemptResult
    }
}

// MARK: - RequestRouter

/// Resolves routing decisions for public-path inference requests.
///
/// This is the integration point between the planner/attempt runner
/// infrastructure and the public request APIs (Responses, Chat).
///
/// Resolution flow:
/// 1. Parse the model reference
/// 2. If a cached plan exists, build candidates from it
/// 3. Run the candidate attempt loop (with runtime/gate checks)
/// 4. If no plan and no candidates, fall back to direct hosted gateway
/// 5. Build RouteMetadata and RoutingDecisionResult
///
/// The router itself does NOT perform inference. It resolves *where*
/// inference should run and returns the decision for the caller to act on.
public final class RequestRouter: @unchecked Sendable {
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "RequestRouter")

    public init() {}

    /// Resolve a routing decision for the given context.
    ///
    /// - Parameters:
    ///   - context: All inputs for the routing decision.
    ///   - runtimeChecker: Optional checker for engine availability.
    ///   - gateEvaluator: Optional evaluator for per-request gates.
    /// - Returns: A ``RoutingDecisionResult`` with locality, mode, engine, and metadata.
    public func resolve(
        context: RequestRoutingContext,
        runtimeChecker: (any AttemptRuntimeChecker)? = nil,
        gateEvaluator: (any AttemptGateEvaluator)? = nil
    ) -> RoutingDecisionResult {
        let routeId = UUID().uuidString
        let parsedRef = ParsedModelRef.parse(context.model)
        let policyString = context.routingPolicy?.rawValue

        // Determine fallback policy from routing policy.
        let fallbackAllowed = Self.isFallbackAllowed(context.routingPolicy)

        // Build candidates from plan, if available.
        if let plan = context.cachedPlan {
            let candidates = Self.candidatesFromPlan(plan)
            guard !candidates.isEmpty else {
                return directHostedFallback(
                    routeId: routeId,
                    parsedRef: parsedRef,
                    policy: policyString,
                    plannerSource: "cache"
                )
            }

            let runner = CandidateAttemptRunner(
                fallbackAllowed: fallbackAllowed,
                streaming: context.streaming
            )

            let loopResult = runner.run(
                candidates: candidates,
                runtimeChecker: runtimeChecker,
                gateEvaluator: gateEvaluator
            )

            if let selected = loopResult.selectedAttempt {
                let metadata = RouteMetadata(
                    routeId: routeId,
                    planId: plan.serverGeneratedAt.isEmpty ? nil : plan.serverGeneratedAt,
                    plannerSource: "cache",
                    policy: plan.policy,
                    finalLocality: selected.locality,
                    engine: selected.engine,
                    modelRefKind: parsedRef.kind.rawValue,
                    modelRef: parsedRef.raw,
                    appSlug: parsedRef.appSlug,
                    deploymentId: parsedRef.deploymentId,
                    experimentId: parsedRef.experimentId,
                    variantId: parsedRef.variantId,
                    cacheStatus: selected.artifact?.cache.status,
                    fallbackUsed: loopResult.fallbackUsed,
                    fallbackTriggerCode: loopResult.fallbackTrigger?.code,
                    candidateAttempts: loopResult.attempts.count
                )

                let canonical = CanonicalRouteMetadata(
                    status: "selected",
                    execution: RouteExecution(
                        locality: selected.locality,
                        mode: selected.mode,
                        engine: selected.engine
                    ),
                    model: RouteModel(
                        requested: RouteModelRequested(
                            ref: parsedRef.raw,
                            kind: parsedRef.kind.rawValue
                        )
                    ),
                    artifact: selected.artifact.map { att in
                        RouteArtifact(cache: ArtifactCache(status: att.cache.status))
                    },
                    planner: PlannerInfo(source: "cache"),
                    fallback: FallbackInfo(used: loopResult.fallbackUsed)
                )

                return RoutingDecisionResult(
                    locality: selected.locality,
                    mode: selected.mode,
                    engine: selected.engine,
                    routeMetadata: metadata,
                    canonicalMetadata: canonical,
                    attemptResult: loopResult
                )
            }

            // Plan had candidates but none passed — fall back to hosted if allowed.
            if fallbackAllowed {
                logger.debug("All plan candidates failed; falling back to hosted gateway")
                return directHostedFallback(
                    routeId: routeId,
                    parsedRef: parsedRef,
                    policy: policyString,
                    plannerSource: "cache",
                    attemptResult: loopResult
                )
            }

            // No fallback allowed — return a failed decision with the attempt loop intact.
            let metadata = RouteMetadata(
                routeId: routeId,
                plannerSource: "cache",
                policy: policyString,
                finalLocality: "local",
                modelRefKind: parsedRef.kind.rawValue,
                modelRef: parsedRef.raw,
                appSlug: parsedRef.appSlug,
                deploymentId: parsedRef.deploymentId,
                experimentId: parsedRef.experimentId,
                variantId: parsedRef.variantId,
                fallbackUsed: false,
                candidateAttempts: loopResult.attempts.count
            )
            let canonical = CanonicalRouteMetadata(
                status: "unavailable",
                execution: nil,
                model: RouteModel(
                    requested: RouteModelRequested(
                        ref: parsedRef.raw,
                        kind: parsedRef.kind.rawValue
                    )
                ),
                planner: PlannerInfo(source: "cache"),
                fallback: FallbackInfo(used: false),
                reason: RouteReason(
                    code: "no_candidate_passed",
                    message: "All plan candidates failed and fallback is not allowed"
                )
            )
            return RoutingDecisionResult(
                locality: "local",
                mode: "sdk_runtime",
                routeMetadata: metadata,
                canonicalMetadata: canonical,
                attemptResult: loopResult
            )
        }

        // No plan available — fall back to direct hosted gateway.
        logger.debug("No plan available for \(context.model); routing to hosted gateway")
        return directHostedFallback(
            routeId: routeId,
            parsedRef: parsedRef,
            policy: policyString,
            plannerSource: "offline"
        )
    }

    // MARK: - Private

    /// Build candidate inputs from a plan response.
    static func candidatesFromPlan(_ plan: RuntimePlanResponse) -> [AttemptCandidateInput] {
        var result: [AttemptCandidateInput] = []

        for candidate in plan.candidates {
            result.append(AttemptCandidateInput(
                candidate: candidate,
                gates: candidate.gates
            ))
        }

        // Append fallback candidates after primary candidates.
        for candidate in plan.fallbackCandidates {
            result.append(AttemptCandidateInput(
                candidate: candidate,
                gates: candidate.gates
            ))
        }

        return result
    }

    /// Whether the given routing policy allows fallback to cloud.
    static func isFallbackAllowed(_ policy: AppRoutingPolicy?) -> Bool {
        guard let policy else { return true }
        switch policy {
        case .localOnly, .private:
            return false
        case .cloudOnly, .localFirst, .cloudFirst, .auto, .performanceFirst:
            return true
        }
    }

    /// Build a direct hosted-gateway routing decision (no plan, no local candidate).
    private func directHostedFallback(
        routeId: String,
        parsedRef: ParsedModelRef,
        policy: String?,
        plannerSource: String,
        attemptResult: AttemptLoopResult? = nil
    ) -> RoutingDecisionResult {
        let metadata = RouteMetadata(
            routeId: routeId,
            plannerSource: plannerSource,
            policy: policy,
            finalLocality: "cloud",
            modelRefKind: parsedRef.kind.rawValue,
            modelRef: parsedRef.raw,
            appSlug: parsedRef.appSlug,
            deploymentId: parsedRef.deploymentId,
            experimentId: parsedRef.experimentId,
            variantId: parsedRef.variantId,
            fallbackUsed: attemptResult?.fallbackUsed ?? false,
            fallbackTriggerCode: attemptResult?.fallbackTrigger?.code,
            candidateAttempts: attemptResult?.attempts.count ?? 0
        )

        let canonical = CanonicalRouteMetadata(
            status: "selected",
            execution: RouteExecution(
                locality: "cloud",
                mode: "hosted_gateway"
            ),
            model: RouteModel(
                requested: RouteModelRequested(
                    ref: parsedRef.raw,
                    kind: parsedRef.kind.rawValue
                )
            ),
            planner: PlannerInfo(source: plannerSource),
            fallback: FallbackInfo(used: attemptResult?.fallbackUsed ?? false)
        )

        return RoutingDecisionResult(
            locality: "cloud",
            mode: "hosted_gateway",
            routeMetadata: metadata,
            canonicalMetadata: canonical,
            attemptResult: attemptResult ?? AttemptLoopResult()
        )
    }
}

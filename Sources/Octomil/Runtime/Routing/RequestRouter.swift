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
/// - `dep_<id>` — deployment ID
/// - `exp_<id>` — experiment variant ref
/// - anything else — plain model ID (passed through to the runtime)
public struct ParsedModelRef: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case appRef = "app_ref"
        case capabilityRef = "capability_ref"
        case deploymentRef = "deployment_ref"
        case experimentRef = "experiment_ref"
        case plainId = "plain_id"
    }

    public let kind: Kind
    public let raw: String

    /// Parse a model string into a typed reference.
    public static func parse(_ model: String) -> ParsedModelRef {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("@app/") {
            return ParsedModelRef(kind: .appRef, raw: trimmed)
        }
        if trimmed.hasPrefix("@capability/") {
            return ParsedModelRef(kind: .capabilityRef, raw: trimmed)
        }
        if trimmed.hasPrefix("dep_") {
            return ParsedModelRef(kind: .deploymentRef, raw: trimmed)
        }
        if trimmed.hasPrefix("exp_") {
            return ParsedModelRef(kind: .experimentRef, raw: trimmed)
        }
        return ParsedModelRef(kind: .plainId, raw: trimmed)
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

// MARK: - RouteMetadata

/// Privacy-safe metadata attached to every routed request.
///
/// NEVER contains: prompt, input, output, audio, filePath, content, messages.
/// Only operational metadata for routing telemetry and debugging.
public struct RouteMetadata: Sendable, Equatable {
    /// Unique ID for this routing decision.
    public let routeId: String
    /// The plan ID from the server planner, if a plan was used.
    public let planId: String?
    /// How the plan was obtained: "cache", "server_plan", "local_default", "none".
    public let plannerSource: String
    /// The routing policy that was applied.
    public let policy: String?
    /// Final locality where inference ran.
    public let finalLocality: String
    /// Engine used for inference.
    public let engine: String?
    /// The parsed model reference kind.
    public let modelRefKind: String
    /// Whether fallback was triggered during this request.
    public let fallbackUsed: Bool
    /// Machine-readable code for what triggered the fallback.
    public let fallbackTriggerCode: String?
    /// Number of candidate attempts evaluated.
    public let candidateAttempts: Int

    public init(
        routeId: String = UUID().uuidString,
        planId: String? = nil,
        plannerSource: String = "none",
        policy: String? = nil,
        finalLocality: String,
        engine: String? = nil,
        modelRefKind: String = "plain_id",
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
    /// Privacy-safe route metadata.
    public let routeMetadata: RouteMetadata
    /// Full attempt loop result for telemetry.
    public let attemptResult: AttemptLoopResult

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
        self.attemptResult = attemptResult
    }
}

// MARK: - RouteEvent

/// Privacy-safe telemetry event emitted after each routed request.
///
/// NEVER contains: prompt, input, output, audio, filePath, content, messages.
public struct RouteEvent: Codable, Sendable, Equatable {
    public let routeId: String
    public let requestId: String
    public let planId: String?
    public let capability: String
    public let policy: String?
    public let plannerSource: String?
    public let finalLocality: String
    public let engine: String?
    public let fallbackUsed: Bool
    public let fallbackTriggerCode: String?
    public let candidateAttempts: Int
    public let modelRefKind: String

    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
        case requestId = "request_id"
        case planId = "plan_id"
        case capability
        case policy
        case plannerSource = "planner_source"
        case finalLocality = "final_locality"
        case engine
        case fallbackUsed = "fallback_used"
        case fallbackTriggerCode = "fallback_trigger_code"
        case candidateAttempts = "candidate_attempts"
        case modelRefKind = "model_ref_kind"
    }

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
        modelRefKind: String = "plain_id"
    ) {
        self.routeId = routeId
        self.requestId = requestId
        self.planId = planId
        self.capability = capability
        self.policy = policy
        self.plannerSource = plannerSource
        self.finalLocality = finalLocality
        self.engine = engine
        self.fallbackUsed = fallbackUsed
        self.fallbackTriggerCode = fallbackTriggerCode
        self.candidateAttempts = candidateAttempts
        self.modelRefKind = modelRefKind
    }

    /// Build a RouteEvent from a RoutingDecisionResult and a request ID.
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
            finalLocality: decision.routeMetadata.finalLocality,
            engine: decision.routeMetadata.engine,
            fallbackUsed: decision.routeMetadata.fallbackUsed,
            fallbackTriggerCode: decision.routeMetadata.fallbackTriggerCode,
            candidateAttempts: decision.routeMetadata.candidateAttempts,
            modelRefKind: decision.routeMetadata.modelRefKind
        )
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
                    fallbackUsed: loopResult.fallbackUsed,
                    fallbackTriggerCode: loopResult.fallbackTrigger?.code,
                    candidateAttempts: loopResult.attempts.count
                )

                return RoutingDecisionResult(
                    locality: selected.locality,
                    mode: selected.mode,
                    engine: selected.engine,
                    routeMetadata: metadata,
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
                fallbackUsed: false,
                candidateAttempts: loopResult.attempts.count
            )
            return RoutingDecisionResult(
                locality: "local",
                mode: "sdk_runtime",
                routeMetadata: metadata,
                attemptResult: loopResult
            )
        }

        // No plan available — fall back to direct hosted gateway.
        logger.debug("No plan available for \(context.model); routing to hosted gateway")
        return directHostedFallback(
            routeId: routeId,
            parsedRef: parsedRef,
            policy: policyString,
            plannerSource: "none"
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
            fallbackUsed: attemptResult?.fallbackUsed ?? false,
            fallbackTriggerCode: attemptResult?.fallbackTrigger?.code,
            candidateAttempts: attemptResult?.attempts.count ?? 0
        )

        return RoutingDecisionResult(
            locality: "cloud",
            mode: "hosted_gateway",
            routeMetadata: metadata,
            attemptResult: attemptResult ?? AttemptLoopResult()
        )
    }
}

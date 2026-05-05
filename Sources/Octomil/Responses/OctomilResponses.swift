import Foundation
import os.log

/// Developer-facing Response API (Layer 2).
///
/// Provides `create()` and `stream()` methods that resolve a ``ModelRuntime``,
/// format the prompt, and return structured responses.
///
/// Production routing path:
/// 1. Parse model reference (app, capability, deployment, experiment, or plain ID)
/// 2. Resolve routing via ``RequestRouter`` using cached plan + attempt loop
/// 3. Dispatch inference to the selected runtime (local or cloud)
/// 4. Attach ``RouteMetadata`` to every ``Response``
/// 5. Emit ``RouteEvent`` telemetry (privacy-safe: no prompt/output/content)
///
/// Fallback semantics:
/// - Non-streaming: fallback is allowed at any point before the response returns
/// - Streaming: fallback is allowed ONLY before the first output token is emitted
///
/// ```swift
/// let responses = OctomilResponses()
/// let response = try await responses.create(
///     ResponseRequest(model: "phi-4-mini", input: [.text("Hello")])
/// )
/// print(response.routeMetadata?.execution?.locality ?? "unknown")
/// ```
public final class OctomilResponses: @unchecked Sendable {
    private let runtimeResolver: ((String) -> ModelRuntime?)?

    /// Optional resolver for ``ModelRef``-based lookups (capability routing).
    /// Set by ``OctomilClient`` when a manifest is configured.
    public var catalogResolver: ((ModelRef) -> ModelRuntime?)?

    /// Device context for cloud fallback auth. Local inference never reads this.
    public var deviceContext: DeviceContext?

    /// Runtime planner for server-plan-aware routing.
    /// When non-nil, `create()`/`stream()` use the planner to build candidates.
    public var planner: RuntimePlanner?

    /// Planner store for cached plan lookups during routing.
    public var plannerStore: RuntimePlannerStore?

    /// Cache of recent responses for conversation chaining via `previousResponseId`.
    private var responseCache: [String: Response] = [:]
    private let cacheLock = NSLock()
    private let maxCacheSize = 100

    private let router = RequestRouter()
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "OctomilResponses")

    public init(runtimeResolver: ((String) -> ModelRuntime?)? = nil, deviceContext: DeviceContext? = nil) {
        self.runtimeResolver = runtimeResolver
        self.deviceContext = deviceContext
    }

    // MARK: - Non-streaming

    public func create(_ request: ResponseRequest) async throws -> Response {
        let effectiveRequest = buildEffectiveRequest(request)
        let runtimeRequest = Self.buildRuntimeRequest(effectiveRequest)

        let routingContext = await buildRoutingContext(request, streaming: false)
        let routed = await router.resolveWithInference(
            context: routingContext,
            outputQualityEvaluator: DefaultOutputQualityEvaluator(),
            candidatesForDecision: { [self] decision in
                buildProductionCandidates(
                    decision: decision,
                    context: routingContext,
                    model: request.model
                )
            }
        ) { [self] candidateInput, attempt in
            let runtime = try resolveRuntimeForAttempt(request: request, attempt: attempt)
            return try await runtime.run(request: runtimeRequest)
        }
        let decision = routed.decision
        let attemptResult = routed.attemptResult

        guard let runtimeResponse = attemptResult.value else {
            if let error = attemptResult.error { throw error }
            throw OctomilResponsesError.noRuntime(request.model)
        }

        // Build RouteMetadata from the decision + attempt results
        let metadata = buildRouteMetadataFromAttemptResult(
            decision: decision,
            attemptResult: attemptResult,
            model: request.model
        )

        let response = buildResponse(
            model: request.model,
            runtimeResponse: runtimeResponse,
            routeMetadata: metadata
        )
        cacheResponse(response)

        // Emit route telemetry (privacy-safe, no content)
        emitRouteTelemetry(
            metadata: metadata,
            requestId: response.id,
            capability: routingContext.capability,
            candidateAttempts: attemptResult.attempts.count,
            fallbackTriggerCode: attemptResult.fallbackTrigger?.code,
            fallbackTriggerStage: attemptResult.fallbackTrigger?.stage
        )

        return response
    }

    // MARK: - Streaming

    public func stream(_ request: ResponseRequest) -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        let effectiveRequest = buildEffectiveRequest(request)

        return AsyncThrowingStream { [weak self] continuation in
            let task = Task {
                do {
                    guard let self = self else {
                        throw OctomilResponsesError.noRuntime(effectiveRequest.model)
                    }

                    let routingContext = await self.buildRoutingContext(request, streaming: true)
                    let decision = self.router.resolve(context: routingContext)
                    let fallbackAllowed = RequestRouter.isFallbackAllowed(request.routing)

                    let candidates = self.buildProductionCandidates(
                        decision: decision,
                        context: routingContext,
                        model: request.model
                    )

                    let attemptRunner = CandidateAttemptRunner(
                        fallbackAllowed: fallbackAllowed,
                        streaming: true
                    )
                    let attemptReadiness = attemptRunner.run(candidates: candidates)
                    guard attemptReadiness.selectedAttempt != nil else {
                        throw OctomilResponsesError.noRuntime(request.model)
                    }

                    var selectedAttempt = attemptReadiness.selectedAttempt!
                    let runtime = try self.resolveRuntimeForAttempt(
                        request: request,
                        attempt: selectedAttempt
                    )

                    let runtimeRequest = Self.buildRuntimeRequest(effectiveRequest)
                    let responseId = Self.generateId()
                    var textParts: [String] = []
                    var toolCallBuffers: [Int: ToolCallBuffer] = [:]
                    var lastUsage: RuntimeUsage?
                    var chunkIndex = 0
                    var firstOutputEmitted = false

                    var fallbackUsed = false
                    var fallbackTriggerCode: String?
                    var candidateAttemptCount = attemptReadiness.attempts.count
                    do {
                        for try await chunk in runtime.stream(request: runtimeRequest) {
                            if let text = chunk.text {
                                firstOutputEmitted = true
                                textParts.append(text)
                                continuation.yield(.textDelta(text))
                            }

                            if let delta = chunk.toolCallDelta {
                                firstOutputEmitted = true
                                var buffer = toolCallBuffers[delta.index] ?? ToolCallBuffer()
                                if let id = delta.id { buffer.id = id }
                                if let name = delta.name { buffer.name = name }
                                if let args = delta.argumentsDelta { buffer.arguments += args }
                                toolCallBuffers[delta.index] = buffer

                                continuation.yield(.toolCallDelta(
                                    index: delta.index,
                                    id: delta.id,
                                    name: delta.name,
                                    argumentsDelta: delta.argumentsDelta
                                ))
                            }

                            if let usage = chunk.usage { lastUsage = usage }

                            // Report chunk telemetry
                            TelemetryQueue.shared?.reportInferenceChunkProduced(
                                modelId: effectiveRequest.model,
                                chunkIndex: chunkIndex
                            )
                            chunkIndex += 1
                        }
                    } catch {
                        // First-token lockout: after first output, fallback is forbidden for streaming.
                        guard attemptRunner.shouldFallbackAfterInferenceError(firstOutputEmitted: firstOutputEmitted),
                              let selectedIndex = attemptReadiness.selectedAttempt?.index,
                              selectedIndex + 1 < candidates.count else {
                            throw error
                        }

                        fallbackUsed = true
                        fallbackTriggerCode = "inference_error_before_first_output"
                        let fallbackCandidates = Array(candidates.dropFirst(selectedIndex + 1))
                        let fallbackReadiness = CandidateAttemptRunner(
                            fallbackAllowed: false,
                            streaming: true
                        ).run(candidates: fallbackCandidates)
                        guard let fallbackAttempt = fallbackReadiness.selectedAttempt else {
                            throw error
                        }
                        selectedAttempt = fallbackAttempt
                        candidateAttemptCount += fallbackReadiness.attempts.count
                        let fallbackRuntime = try self.resolveRuntimeForAttempt(
                            request: request,
                            attempt: fallbackAttempt
                        )
                        for try await chunk in fallbackRuntime.stream(request: runtimeRequest) {
                            if let text = chunk.text {
                                firstOutputEmitted = true
                                textParts.append(text)
                                continuation.yield(.textDelta(text))
                            }

                            if let delta = chunk.toolCallDelta {
                                firstOutputEmitted = true
                                var buffer = toolCallBuffers[delta.index] ?? ToolCallBuffer()
                                if let id = delta.id { buffer.id = id }
                                if let name = delta.name { buffer.name = name }
                                if let args = delta.argumentsDelta { buffer.arguments += args }
                                toolCallBuffers[delta.index] = buffer

                                continuation.yield(.toolCallDelta(
                                    index: delta.index,
                                    id: delta.id,
                                    name: delta.name,
                                    argumentsDelta: delta.argumentsDelta
                                ))
                            }

                            if let usage = chunk.usage { lastUsage = usage }
                            TelemetryQueue.shared?.reportInferenceChunkProduced(
                                modelId: effectiveRequest.model,
                                chunkIndex: chunkIndex
                            )
                            chunkIndex += 1
                        }
                    }

                    var output: [OutputItem] = []
                    let fullText = textParts.joined()
                    if !fullText.isEmpty {
                        output.append(.text(fullText))
                    }
                    for key in toolCallBuffers.keys.sorted() {
                        let buffer = toolCallBuffers[key]!
                        output.append(.toolCall(ResponseToolCall(
                            id: buffer.id ?? Self.generateId(),
                            name: buffer.name ?? "",
                            arguments: buffer.arguments
                        )))
                    }

                    let finishReason = toolCallBuffers.isEmpty ? "stop" : "tool_calls"
                    let usage = lastUsage.map {
                        ResponseUsage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens, totalTokens: $0.totalTokens)
                    }

                    let metadata = RouteMetadata(
                        status: "selected",
                        execution: RouteExecution(
                            locality: selectedAttempt.locality,
                            mode: selectedAttempt.mode,
                            engine: selectedAttempt.engine
                        ),
                        model: decision.routeMetadata.model,
                        artifact: selectedAttempt.artifact.map { artifact in
                            RouteArtifact(id: nil, version: nil, format: nil, digest: nil, cache: ArtifactCache(status: artifact.cache.status, managed_by: nil))
                        },
                        planner: decision.routeMetadata.planner,
                        fallback: FallbackInfo(used: fallbackUsed || attemptReadiness.fallbackUsed, from_attempt: nil, to_attempt: nil, trigger: nil),
                        attempts: nil,
                        reason: RouteReason(
                            code: fallbackTriggerCode ?? attemptReadiness.fallbackTrigger?.code ?? "ok",
                            message: "streaming route selected"
                        )
                    )

                    let response = Response(
                        id: responseId,
                        model: effectiveRequest.model,
                        output: output,
                        finishReason: finishReason,
                        usage: usage,
                        routeMetadata: metadata
                    )
                    self.cacheResponse(response)

                    // Emit route telemetry
                    self.emitRouteTelemetry(
                        metadata: metadata,
                        requestId: responseId,
                        capability: routingContext.capability,
                        candidateAttempts: candidateAttemptCount,
                        fallbackTriggerCode: fallbackTriggerCode ?? attemptReadiness.fallbackTrigger?.code,
                        fallbackTriggerStage: attemptReadiness.fallbackTrigger?.stage
                    )

                    continuation.yield(.done(response))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Routing Context

    /// Build a ``RequestRoutingContext`` from the request and available plan cache.
    private func buildRoutingContext(_ request: ResponseRequest, streaming: Bool) async -> RequestRoutingContext {
        // Try to look up a cached plan from the planner store
        var cachedPlan: RuntimePlanResponse?
        if let store = plannerStore {
            let cacheKey = RuntimePlannerStore.makeCacheKey([
                "model": request.model,
                "capability": "chat",
                "policy": request.routing?.rawValue ?? "auto",
                "sdk_version": OctomilVersion.current,
            ])
            cachedPlan = store.getPlan(cacheKey: cacheKey)
        }

        if cachedPlan == nil, let planner {
            let policy = request.routing?.rawValue ?? "local_first"
            let selection = await planner.resolve(
                model: request.model,
                capability: "chat",
                routingPolicy: policy,
                allowNetwork: request.routing != .private
            )
            let primary = RuntimeCandidatePlan(
                locality: selection.locality,
                priority: 0,
                confidence: 1.0,
                reason: selection.reason.isEmpty ? "runtime planner selection" : selection.reason,
                engine: selection.engine,
                artifact: selection.artifact
            )
            cachedPlan = RuntimePlanResponse(
                model: request.model,
                capability: "chat",
                policy: policy,
                candidates: [primary],
                fallbackCandidates: selection.fallbackCandidates,
                fallbackAllowed: Self.isPolicyFallbackAllowed(request.routing),
                serverGeneratedAt: selection.source
            )
        }

        return RequestRoutingContext(
            model: request.model,
            capability: "chat",
            streaming: streaming,
            cachedPlan: cachedPlan,
            routingPolicy: request.routing
        )
    }

    private static func isPolicyFallbackAllowed(_ policy: AppRoutingPolicy?) -> Bool {
        guard let policy else { return true }
        switch policy {
        case .private, .localOnly:
            return false
        case .auto, .cloudFirst, .cloudOnly, .localFirst, .performanceFirst:
            return true
        }
    }

    /// Build production candidates from the routing decision.
    ///
    /// If the router produced candidates from a plan, use those. Otherwise,
    /// build a single synthetic candidate from the registered runtime.
    private func buildProductionCandidates(
        decision: RoutingDecisionResult,
        context: RequestRoutingContext,
        model: String
    ) -> [AttemptCandidateInput] {
        if let plan = context.cachedPlan {
            return RequestRouter.candidatesFromPlan(plan)
        }

        let attempts = decision.attemptResult.attempts
        if !attempts.isEmpty {
            // Re-derive candidates from the plan if available
            // The router already evaluated them but we re-build for runWithInference
            return decision.attemptResult.attempts.map { attempt in
                AttemptCandidateInput(candidate: RuntimeCandidatePlan(
                    locality: attempt.locality == "cloud" ? .cloud : .local,
                    priority: attempt.index,
                    confidence: 1.0,
                    reason: attempt.reason.message,
                    engine: attempt.engine
                ))
            }
        }

        if shouldPreferLocalRuntimeWithoutPlan(context.routingPolicy), hasLocalRuntime(for: model) {
            return [AttemptCandidateInput(candidate: RuntimeCandidatePlan(
                locality: .local,
                priority: 0,
                confidence: 0.7,
                reason: "offline local runtime available",
                engine: "registered"
            ))]
        }

        // Fallback: single candidate from the decision locality
        let locality: RuntimeLocality = decision.locality == "cloud" ? .cloud : .local
        return [AttemptCandidateInput(candidate: RuntimeCandidatePlan(
            locality: locality,
            priority: 0,
            confidence: 1.0,
            reason: "direct routing: \(decision.routeMetadata.planner.source)",
            engine: decision.engine ?? "registered"
        ))]
    }

    private func shouldPreferLocalRuntimeWithoutPlan(_ policy: AppRoutingPolicy?) -> Bool {
        guard let policy else { return true }
        switch policy {
        case .cloudOnly, .cloudFirst:
            return false
        case .private, .localOnly, .localFirst, .performanceFirst, .auto:
            return true
        }
    }

    private func hasLocalRuntime(for model: String) -> Bool {
        if let resolver = runtimeResolver, resolver(model) != nil {
            return true
        }
        if ModelRuntimeRegistry.shared.resolve(modelId: model) != nil {
            return true
        }
        return false
    }

    /// Resolve a runtime for a specific attempt, respecting the locality and engine.
    private func resolveRuntimeForAttempt(
        request: ResponseRequest,
        attempt: RouteAttempt
    ) throws -> ModelRuntime {
        // For cloud locality, check if we have auth, then try the runtime resolver chain
        // For local locality, try the normal resolution chain

        // 1. Try catalog resolver with modelRef
        if let ref = request.modelRef, let resolver = catalogResolver, let runtime = resolver(ref) {
            return runtime
        }

        // 2. Try custom runtime resolver
        if let resolver = runtimeResolver, let runtime = resolver(request.model) {
            return runtime
        }

        // 3. Fall back to global registry
        if let runtime = ModelRuntimeRegistry.shared.resolve(modelId: request.model) {
            return runtime
        }

        throw OctomilResponsesError.noRuntime(request.model)
    }

    /// Build RouteMetadata from an AttemptInferenceResult.
    private func buildRouteMetadataFromAttemptResult<V: Sendable>(
        decision: RoutingDecisionResult,
        attemptResult: AttemptInferenceResult<V>,
        model: String
    ) -> RouteMetadata {
        let selected = attemptResult.selectedAttempt
        return RouteMetadata(
            status: selected == nil ? "unavailable" : "selected",
            execution: selected.map { attempt in
                RouteExecution(
                    locality: attempt.locality,
                    mode: attempt.mode,
                    engine: attempt.engine
                )
            },
            model: decision.routeMetadata.model,
            artifact: selected?.artifact.map { artifact in
                RouteArtifact(id: nil, version: nil, format: nil, digest: nil, cache: ArtifactCache(status: artifact.cache.status, managed_by: nil))
            } ?? decision.routeMetadata.artifact,
            planner: decision.routeMetadata.planner,
            fallback: FallbackInfo(used: attemptResult.fallbackUsed, from_attempt: nil, to_attempt: nil, trigger: nil),
            attempts: nil,
            reason: RouteReason(
                code: attemptResult.fallbackTrigger?.code ?? (selected == nil ? "no_candidate" : "ok"),
                message: selected?.reason.message ?? "route resolved"
            )
        )
    }

    /// Emit route telemetry event. Privacy-safe: no prompt/output/content.
    private func emitRouteTelemetry(
        metadata: RouteMetadata,
        requestId: String,
        capability: String,
        candidateAttempts: Int,
        fallbackTriggerCode: String? = nil,
        fallbackTriggerStage: String? = nil
    ) {
        let routeEvent = RouteEvent(
            requestId: requestId,
            capability: capability,
            plannerSource: metadata.planner.source,
            selectedLocality: metadata.execution?.locality ?? "unavailable",
            finalMode: metadata.execution?.mode ?? "unavailable",
            engine: metadata.execution?.engine,
            fallbackUsed: metadata.fallback.used,
            fallbackTriggerCode: fallbackTriggerCode,
            fallbackTriggerStage: fallbackTriggerStage,
            candidateAttempts: candidateAttempts,
            modelRef: metadata.model.requested.ref,
            modelRefKind: metadata.model.requested.kind.rawValue,
            artifactId: metadata.artifact?.id,
            cacheStatus: metadata.artifact?.cache?.status
        )
        TelemetryQueue.shared?.reportRouteEvent(routeEvent)
    }

    // MARK: - Request Building

    /// Build effective request by prepending instructions and previous response context.
    private func buildEffectiveRequest(_ request: ResponseRequest) -> ResponseRequest {
        var effectiveInput = request.input

        // Prepend previous response context for conversation chaining
        if let previousId = request.previousResponseId {
            cacheLock.lock()
            let previous = responseCache[previousId]
            cacheLock.unlock()

            if let previous = previous {
                let textContent = previous.output.compactMap { item -> ContentPart? in
                    if case .text(let text) = item { return .text(text) }
                    return nil
                }
                let toolCalls = previous.output.compactMap { item -> ResponseToolCall? in
                    if case .toolCall(let call) = item { return call }
                    return nil
                }
                effectiveInput.insert(
                    .assistant(
                        content: textContent.isEmpty ? nil : textContent,
                        toolCalls: toolCalls.isEmpty ? nil : toolCalls
                    ),
                    at: 0
                )
            }
        }

        // Prepend instructions as a system message
        if let instructions = request.instructions {
            effectiveInput.insert(.system(instructions), at: 0)
        }

        return ResponseRequest(
            model: request.model,
            input: effectiveInput,
            tools: request.tools,
            toolChoice: request.toolChoice,
            responseFormat: request.responseFormat,
            stream: request.stream,
            maxOutputTokens: request.maxOutputTokens,
            temperature: request.temperature,
            topP: request.topP,
            stop: request.stop,
            metadata: request.metadata,
            instructions: nil,
            previousResponseId: nil,
            modelRef: request.modelRef,
            routing: request.routing,
            repetitionPenalty: request.repetitionPenalty
        )
    }

    /// Cache a response for later conversation chaining.
    private func cacheResponse(_ response: Response) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if responseCache.count >= maxCacheSize {
            if let firstKey = responseCache.keys.first {
                responseCache.removeValue(forKey: firstKey)
            }
        }
        responseCache[response.id] = response
    }

    static func buildRuntimeRequest(_ request: ResponseRequest) -> RuntimeRequest {
        var messages: [RuntimeMessage] = []

        for item in request.input {
            switch item {
            case .system(let content):
                messages.append(RuntimeMessage(role: .system, parts: [.text(content)]))
            case .user(let parts):
                let runtimeParts = parts.map { part -> RuntimeContentPart in
                    switch part {
                    case .text(let text): return .text(text)
                    case .image(let data, _, let mediaType, _):
                        let decoded = data.flatMap { Data(base64Encoded: $0) } ?? Data()
                        return .image(data: decoded, mediaType: mediaType ?? "image/png")
                    case .audio(let data, let mediaType):
                        let decoded = Data(base64Encoded: data) ?? Data()
                        return .audio(data: decoded, mediaType: mediaType)
                    case .file(let data, let mediaType, _):
                        let decoded = Data(base64Encoded: data) ?? Data()
                        let mt = mediaType.lowercased()
                        if mt.hasPrefix("image/") { return .image(data: decoded, mediaType: mediaType) }
                        if mt.hasPrefix("audio/") { return .audio(data: decoded, mediaType: mediaType) }
                        if mt.hasPrefix("video/") { return .video(data: decoded, mediaType: mediaType) }
                        return .text("[file: unsupported type \(mediaType)]")
                    }
                }
                messages.append(RuntimeMessage(role: .user, parts: runtimeParts))
            case .assistant(let content, let toolCalls):
                var parts: [RuntimeContentPart] = []
                if let content = content {
                    for p in content {
                        if case .text(let text) = p { parts.append(.text(text)) }
                    }
                }
                if let calls = toolCalls {
                    for call in calls {
                        parts.append(.text("{\"tool_call\": {\"name\": \"\(call.name)\", \"arguments\": \(call.arguments)}}"))
                    }
                }
                if parts.isEmpty { parts.append(.text("")) }
                messages.append(RuntimeMessage(role: .assistant, parts: parts))
            case .toolResult(_, let content):
                messages.append(RuntimeMessage(role: .tool, parts: [.text(content)]))
            }
        }

        let toolDefs: [RuntimeToolDef]? = request.tools.isEmpty ? nil : request.tools.map { tool in
            RuntimeToolDef(
                name: tool.function.name,
                description: tool.function.description,
                parametersSchema: nil
            )
        }

        let jsonSchema: String?
        switch request.responseFormat {
        case .jsonSchema(let schema): jsonSchema = schema
        case .jsonObject: jsonSchema = "{}"
        case .text: jsonSchema = nil
        }

        return RuntimeRequest(
            messages: messages,
            generationConfig: GenerationConfig(
                maxTokens: request.maxOutputTokens ?? 512,
                temperature: request.temperature ?? 0.7,
                topP: request.topP ?? 1.0,
                stop: request.stop,
                repetitionPenalty: request.repetitionPenalty
            ),
            toolDefinitions: toolDefs,
            jsonSchema: jsonSchema
        )
    }

    private func buildResponse(
        model: String,
        runtimeResponse: RuntimeResponse,
        routeMetadata: RouteMetadata? = nil
    ) -> Response {
        var output: [OutputItem] = []

        if !runtimeResponse.text.isEmpty {
            output.append(.text(runtimeResponse.text))
        }

        if let toolCalls = runtimeResponse.toolCalls {
            for call in toolCalls {
                output.append(.toolCall(ResponseToolCall(id: call.id, name: call.name, arguments: call.arguments)))
            }
        }

        let finishReason: String
        if let calls = runtimeResponse.toolCalls, !calls.isEmpty {
            finishReason = "tool_calls"
        } else {
            finishReason = runtimeResponse.finishReason
        }

        let usage = runtimeResponse.usage.map {
            ResponseUsage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens, totalTokens: $0.totalTokens)
        }

        return Response(
            id: Self.generateId(),
            model: model,
            output: output,
            finishReason: finishReason,
            usage: usage,
            routeMetadata: routeMetadata
        )
    }

    static func generateId() -> String {
        "resp_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))"
    }

    private struct ToolCallBuffer {
        var id: String?
        var name: String?
        var arguments: String = ""
    }
}

/// Errors from the Response API.
public enum OctomilResponsesError: Error, LocalizedError {
    case noRuntime(String)
    case runtimeNotFound(String)
    case authRequired(String)

    public var errorDescription: String? {
        switch self {
        case .noRuntime(let model):
            return "No ModelRuntime registered for model: \(model)"
        case .runtimeNotFound(let message):
            return message
        case .authRequired(let model):
            return "Cloud fallback for model '\(model)' requires authentication, but no valid token is available"
        }
    }
}

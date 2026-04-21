import Foundation

/// Developer-facing Response API (Layer 2).
///
/// Provides `create()` and `stream()` methods that resolve a ``ModelRuntime``,
/// format the prompt, and return structured responses.
///
/// ```swift
/// let responses = OctomilResponses()
/// let response = try await responses.create(
///     ResponseRequest(model: "phi-4-mini", input: [.text("Hello")])
/// )
/// ```
public final class OctomilResponses: @unchecked Sendable {
    private let runtimeResolver: ((String) -> ModelRuntime?)?

    /// Optional resolver for ``ModelRef``-based lookups (capability routing).
    /// Set by ``OctomilClient`` when a manifest is configured.
    public var catalogResolver: ((ModelRef) -> ModelRuntime?)?

    /// Device context for cloud fallback auth. Local inference never reads this.
    public var deviceContext: DeviceContext?

    /// Cache of recent responses for conversation chaining via `previousResponseId`.
    private var responseCache: [String: Response] = [:]
    private let cacheLock = NSLock()
    private let maxCacheSize = 100

    public init(runtimeResolver: ((String) -> ModelRuntime?)? = nil, deviceContext: DeviceContext? = nil) {
        self.runtimeResolver = runtimeResolver
        self.deviceContext = deviceContext
    }

    // MARK: - Non-streaming

    public func create(_ request: ResponseRequest) async throws -> Response {
        let runtime = try resolveRuntimeForRequest(request)
        let effectiveRequest = buildEffectiveRequest(request)
        let runtimeRequest = Self.buildRuntimeRequest(effectiveRequest)
        let requestId = Self.generateRequestId()
        let attemptResult = await CandidateAttemptRunner(fallbackAllowed: false).runWithInference(
            candidates: [Self.attemptCandidate(model: request.model)]
        ) { _, _ in
            try await runtime.run(request: runtimeRequest)
        }
        guard let runtimeResponse = attemptResult.value else {
            if let error = attemptResult.error { throw error }
            throw OctomilResponsesError.noRuntime(request.model)
        }
        let response = buildResponse(model: request.model, runtimeResponse: runtimeResponse)
        cacheResponse(response)
        emitRouteEvent(for: request, requestId: requestId, attemptResult: attemptResult)
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
                    let runtime = try self.resolveRuntimeForRequest(request)

                    let runtimeRequest = Self.buildRuntimeRequest(effectiveRequest)
                    let attemptRunner = CandidateAttemptRunner(fallbackAllowed: false, streaming: true)
                    let requestId = Self.generateRequestId()
                    let attemptReadiness = attemptRunner.run(candidates: [Self.attemptCandidate(model: request.model)])
                    guard attemptReadiness.selectedAttempt != nil else {
                        throw OctomilResponsesError.noRuntime(request.model)
                    }
                    let responseId = Self.generateId()
                    var textParts: [String] = []
                    var toolCallBuffers: [Int: ToolCallBuffer] = [:]
                    var lastUsage: RuntimeUsage?
                    var chunkIndex = 0
                    var firstOutputEmitted = false

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
                        _ = attemptRunner.shouldFallbackAfterInferenceError(firstOutputEmitted: firstOutputEmitted)
                        throw error
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

                    let response = Response(
                        id: responseId,
                        model: effectiveRequest.model,
                        output: output,
                        finishReason: finishReason,
                        usage: usage
                    )
                    self.cacheResponse(response)
                    self.emitRouteEvent(for: request, requestId: requestId, attemptResult: attemptReadiness)
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

    // MARK: - Private

    private func emitRouteEvent(
        for request: ResponseRequest,
        requestId: String,
        attemptResult: AttemptLoopResult
    ) {
        emitRouteEvent(
            for: request,
            requestId: requestId,
            selectedAttempt: attemptResult.selectedAttempt,
            attempts: attemptResult.attempts,
            fallbackUsed: attemptResult.fallbackUsed,
            fallbackTrigger: attemptResult.fallbackTrigger
        )
    }

    private func emitRouteEvent(
        for request: ResponseRequest,
        requestId: String,
        attemptResult: AttemptInferenceResult<RuntimeResponse>
    ) {
        emitRouteEvent(
            for: request,
            requestId: requestId,
            selectedAttempt: attemptResult.selectedAttempt,
            attempts: attemptResult.attempts,
            fallbackUsed: attemptResult.fallbackUsed,
            fallbackTrigger: attemptResult.fallbackTrigger
        )
    }

    private func emitRouteEvent(
        for request: ResponseRequest,
        requestId: String,
        selectedAttempt: RouteAttempt?,
        attempts: [RouteAttempt],
        fallbackUsed: Bool,
        fallbackTrigger: FallbackTrigger?
    ) {
        guard selectedAttempt != nil else { return }
        TelemetryQueue.shared?.reportRouteEvent(
            RouteEvent(
                requestId: requestId,
                capability: "responses",
                policy: request.routing?.rawValue,
                plannerSource: "offline",
                selectedLocality: selectedAttempt?.locality ?? "unknown",
                finalMode: selectedAttempt?.mode ?? "unknown",
                engine: selectedAttempt?.engine,
                fallbackUsed: fallbackUsed,
                fallbackTriggerCode: fallbackTrigger?.code,
                fallbackTriggerStage: fallbackTrigger?.stage,
                candidateAttempts: attempts.count,
                modelRef: request.model,
                modelRefKind: modelRefKind(request.modelRef),
                artifactId: selectedAttempt?.artifact?.id
            )
        )
    }

    private func modelRefKind(_ ref: ModelRef?) -> String? {
        guard let ref else { return nil }
        switch ref {
        case .id:
            return "id"
        case .capability:
            return "capability"
        }
    }

    private static func generateRequestId() -> String {
        "req_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
    }

    private static func attemptCandidate(model: String) -> AttemptCandidateInput {
        AttemptCandidateInput(candidate: RuntimeCandidatePlan(
            locality: .local,
            priority: 0,
            confidence: 1,
            reason: "registered model runtime",
            engine: "registered"
        ))
    }

    /// Resolve a runtime for a request, checking catalog first.
    ///
    /// Resolution order:
    /// 1. ``modelRef`` via ``catalogResolver`` (capability or ID routing)
    /// 2. Custom ``runtimeResolver`` closure (model ID)
    /// 3. ``ModelRuntimeRegistry`` (model ID)
    private func resolveRuntimeForRequest(_ request: ResponseRequest) throws -> ModelRuntime {
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
            // Evict the first entry (oldest insertion order is not guaranteed,
            // but this keeps it bounded).
            if let firstKey = responseCache.keys.first {
                responseCache.removeValue(forKey: firstKey)
            }
        }
        responseCache[response.id] = response
    }

    private static func buildRuntimeRequest(_ request: ResponseRequest) -> RuntimeRequest {
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

    private func buildResponse(model: String, runtimeResponse: RuntimeResponse) -> Response {
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
            usage: usage
        )
    }

    private static func generateId() -> String {
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

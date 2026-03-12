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

    /// Cache of recent responses for conversation chaining via `previousResponseId`.
    private var responseCache: [String: Response] = [:]
    private let cacheLock = NSLock()
    private let maxCacheSize = 100

    public init(runtimeResolver: ((String) -> ModelRuntime?)? = nil) {
        self.runtimeResolver = runtimeResolver
    }

    // MARK: - Non-streaming

    public func create(_ request: ResponseRequest) async throws -> Response {
        let runtime = try resolveRuntime(request.model)
        let effectiveRequest = buildEffectiveRequest(request)
        let runtimeRequest = Self.buildRuntimeRequest(effectiveRequest)
        let runtimeResponse = try await runtime.run(request: runtimeRequest)
        let response = buildResponse(model: request.model, runtimeResponse: runtimeResponse)
        cacheResponse(response)
        return response
    }

    // MARK: - Streaming

    public func stream(_ request: ResponseRequest) -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        let runtimeResolver = self.runtimeResolver
        let effectiveRequest = buildEffectiveRequest(request)

        return AsyncThrowingStream { [weak self] continuation in
            let task = Task {
                do {
                    let runtime: ModelRuntime
                    if let resolver = runtimeResolver, let resolved = resolver(effectiveRequest.model) {
                        runtime = resolved
                    } else if let resolved = ModelRuntimeRegistry.shared.resolve(modelId: effectiveRequest.model) {
                        runtime = resolved
                    } else {
                        throw OctomilResponsesError.noRuntime(effectiveRequest.model)
                    }

                    let runtimeRequest = Self.buildRuntimeRequest(effectiveRequest)
                    let responseId = Self.generateId()
                    var textParts: [String] = []
                    var toolCallBuffers: [Int: ToolCallBuffer] = [:]
                    var lastUsage: RuntimeUsage?
                    var chunkIndex = 0

                    for try await chunk in runtime.stream(request: runtimeRequest) {
                        if let text = chunk.text {
                            textParts.append(text)
                            continuation.yield(.textDelta(text))
                        }

                        if let delta = chunk.toolCallDelta {
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
                    self?.cacheResponse(response)
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

    private func resolveRuntime(_ model: String) throws -> ModelRuntime {
        if let resolver = runtimeResolver, let runtime = resolver(model) {
            return runtime
        }
        if let runtime = ModelRuntimeRegistry.shared.resolve(modelId: model) {
            return runtime
        }
        throw OctomilResponsesError.noRuntime(model)
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
            previousResponseId: nil
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
        let prompt = PromptFormatter.format(input: request.input, tools: request.tools, toolChoice: request.toolChoice)
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
            prompt: prompt,
            maxTokens: request.maxOutputTokens ?? 512,
            temperature: request.temperature ?? 0.7,
            topP: request.topP ?? 1.0,
            stop: request.stop,
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

    public var errorDescription: String? {
        switch self {
        case .noRuntime(let model):
            return "No ModelRuntime registered for model: \(model)"
        case .runtimeNotFound(let message):
            return message
        }
    }
}

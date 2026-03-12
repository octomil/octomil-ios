import Foundation

/// OpenAI-compatible chat interface — **compatibility shim** over ``OctomilResponses``.
///
/// All inference is delegated to the Response API. This class converts
/// `ChatRequest` / `ChatCompletion` to and from the Response API types.
///
/// ```swift
/// let chat = OctomilChat(modelName: "phi-4-mini", responses: responses)
///
/// // Non-streaming:
/// let response = try await chat.create("What is ML?")
/// print(response.choices[0].message.content ?? "")
///
/// // Streaming:
/// for try await chunk in chat.stream("Explain neural networks") {
///     print(chunk.choices[0].delta.content ?? "", terminator: "")
/// }
/// ```
public final class OctomilChat: @unchecked Sendable {
    /// The logical model name.
    public let modelName: String

    private let responses: OctomilResponses

    // Legacy init kept for backward compatibility (engine/runtime are ignored;
    // all inference goes through OctomilResponses).
    public init(modelName: String, engine: StreamingInferenceEngine, runtime: LLMRuntime? = nil) {
        self.modelName = modelName
        self.responses = OctomilResponses()
    }

    public init(modelName: String, responses: OctomilResponses) {
        self.modelName = modelName
        self.responses = responses
    }

    // MARK: - Non-streaming

    /// Create a chat completion (non-streaming).
    ///
    /// Equivalent to OpenAI's `client.chat.completions.create(stream: false)`.
    ///
    /// - Parameters:
    ///   - request: The chat request parameters.
    ///   - model: Optional model override. When provided, takes precedence over the
    ///     constructor default and any model set on the request itself.
    public func create(_ request: ChatRequest, model: String? = nil) async throws -> ChatCompletion {
        let effectiveModel = model ?? request.model ?? modelName
        let responseRequest = Self.toResponseRequest(model: effectiveModel, chat: request)
        let response = try await responses.create(responseRequest)
        return Self.toChatCompletion(response: response, model: effectiveModel)
    }

    /// Convenience: create a completion from a single user message.
    ///
    /// - Parameters:
    ///   - message: The user message string.
    ///   - model: Optional model override.
    public func create(_ message: String, model: String? = nil) async throws -> ChatCompletion {
        try await create(ChatRequest(messages: [.user(message)]), model: model)
    }

    // MARK: - Streaming

    /// Stream a chat completion, yielding chunks as they are generated.
    ///
    /// Equivalent to OpenAI's `client.chat.completions.create(stream: true)`.
    ///
    /// - Parameters:
    ///   - request: The chat request parameters.
    ///   - model: Optional model override. When provided, takes precedence over the
    ///     constructor default and any model set on the request itself.
    public func stream(_ request: ChatRequest, model: String? = nil) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        let effectiveModel = model ?? request.model ?? modelName
        let responseRequest = Self.toResponseRequest(model: effectiveModel, chat: request, stream: true)
        let completionId = "chatcmpl-\(UUID().uuidString.prefix(12))"
        let created = Int(Date().timeIntervalSince1970)
        let modelName = effectiveModel
        let responseStream = responses.stream(responseRequest)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var isFirst = true
                    for try await event in responseStream {
                        switch event {
                        case .textDelta(let text):
                            let chunk = Self.makeChunk(
                                id: completionId, created: created, model: modelName,
                                content: text, role: isFirst ? .assistant : nil
                            )
                            continuation.yield(chunk)
                            isFirst = false

                        case .toolCallDelta(let index, let id, let name, let argsDelta):
                            let tc = ToolCall(
                                id: id ?? "call_\(index)",
                                function: FunctionCall(
                                    name: name ?? "",
                                    arguments: argsDelta ?? ""
                                )
                            )
                            let chunk = ChatCompletionChunk(
                                id: completionId,
                                object: "chat.completion.chunk",
                                created: created,
                                model: modelName,
                                choices: [
                                    ChatCompletionChunk.ChunkChoice(
                                        index: 0,
                                        delta: ChatCompletionChunk.Delta(
                                            role: isFirst ? .assistant : nil,
                                            toolCalls: [tc]
                                        ),
                                        finishReason: nil
                                    ),
                                ]
                            )
                            continuation.yield(chunk)
                            isFirst = false

                        case .done(let response):
                            let finishReason = response.finishReason == "tool_calls" ? "tool_calls" : "stop"
                            let finalChunk = ChatCompletionChunk(
                                id: completionId,
                                object: "chat.completion.chunk",
                                created: created,
                                model: modelName,
                                choices: [
                                    ChatCompletionChunk.ChunkChoice(
                                        index: 0,
                                        delta: ChatCompletionChunk.Delta(),
                                        finishReason: finishReason
                                    ),
                                ]
                            )
                            continuation.yield(finalChunk)

                        case .error:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience: stream a completion from a single user message.
    ///
    /// - Parameters:
    ///   - message: The user message string.
    ///   - model: Optional model override.
    public func stream(_ message: String, model: String? = nil) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        stream(ChatRequest(messages: [.user(message)]), model: model)
    }

    // MARK: - Conversion: ChatRequest → ResponseRequest

    static func toResponseRequest(model: String, chat: ChatRequest, stream: Bool = false) -> ResponseRequest {
        var input: [InputItem] = []

        for msg in chat.messages {
            switch msg.role {
            case .system:
                input.append(.system(msg.content ?? ""))
            case .user:
                input.append(.text(msg.content ?? ""))
            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    let rtcs = toolCalls.map { ResponseToolCall.fromLegacy($0) }
                    input.append(.assistant(content: [.text(msg.content ?? "")], toolCalls: rtcs))
                } else {
                    input.append(.assistant(content: [.text(msg.content ?? "")], toolCalls: nil))
                }
            case .tool:
                input.append(.toolResult(toolCallId: msg.toolCallId ?? "", content: msg.content ?? ""))
            }
        }

        return ResponseRequest(
            model: model,
            input: input,
            tools: chat.tools ?? [],
            stream: stream,
            maxOutputTokens: chat.maxTokens,
            temperature: chat.temperature,
            topP: chat.topP,
            stop: chat.stop
        )
    }

    // MARK: - Conversion: Response → ChatCompletion

    static func toChatCompletion(response: Response, model: String) -> ChatCompletion {
        let completionId = "chatcmpl-\(UUID().uuidString.prefix(12))"

        var contentText: String?
        var toolCalls: [ToolCall]?

        for item in response.output {
            switch item {
            case .text(let text):
                contentText = (contentText ?? "") + text
            case .toolCall(let tc):
                if toolCalls == nil { toolCalls = [] }
                toolCalls?.append(tc.toLegacyToolCall())
            case .jsonOutput(let json):
                contentText = (contentText ?? "") + json
            }
        }

        let finishReason = response.finishReason
        let message: ChatMessage
        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            message = ChatMessage(role: .assistant, content: contentText, toolCalls: toolCalls)
        } else {
            message = ChatMessage(role: .assistant, content: contentText)
        }

        let usage: ChatCompletion.Usage?
        if let ru = response.usage {
            usage = ChatCompletion.Usage(
                promptTokens: ru.promptTokens,
                completionTokens: ru.completionTokens,
                totalTokens: ru.totalTokens
            )
        } else {
            usage = nil
        }

        return ChatCompletion(
            id: completionId,
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [
                ChatCompletion.Choice(
                    index: 0,
                    message: message,
                    finishReason: finishReason
                ),
            ],
            usage: usage
        )
    }

    // MARK: - Helpers

    private static func makeChunk(
        id: String, created: Int, model: String,
        content: String, role: ChatMessage.Role?
    ) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id,
            object: "chat.completion.chunk",
            created: created,
            model: model,
            choices: [
                ChatCompletionChunk.ChunkChoice(
                    index: 0,
                    delta: ChatCompletionChunk.Delta(role: role, content: content),
                    finishReason: nil
                ),
            ]
        )
    }
}

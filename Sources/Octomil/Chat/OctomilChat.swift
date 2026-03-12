import Foundation

/// OpenAI-compatible chat interface for on-device inference.
///
/// Drop-in replacement for OpenAI/Groq client calls — same message format,
/// same response shapes, same streaming semantics. Runs entirely on-device.
///
/// ```swift
/// let chat = OctomilChat(modelName: "phi-4-mini", engine: engine)
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

    private let engine: StreamingInferenceEngine
    private let runtime: LLMRuntime?

    public init(modelName: String, engine: StreamingInferenceEngine, runtime: LLMRuntime? = nil) {
        self.modelName = modelName
        self.engine = engine
        self.runtime = runtime
    }

    // MARK: - Non-streaming

    /// Create a chat completion (non-streaming).
    ///
    /// Equivalent to OpenAI's `client.chat.completions.create(stream: false)`.
    public func create(_ request: ChatRequest) async throws -> ChatCompletion {
        let completionId = "chatcmpl-\(UUID().uuidString.prefix(12))"
        let prompt = formatPrompt(request)
        let config = GenerateConfig(
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            topP: request.topP,
            stop: request.stop
        )
        var tokens: [String] = []

        if let runtime = runtime {
            for try await token in runtime.generate(prompt: prompt, config: config) {
                tokens.append(token)
            }
        } else {
            for try await chunk in engine.generate(input: prompt, modality: .text) {
                tokens.append(String(data: chunk.data, encoding: .utf8) ?? "")
            }
        }

        let fullContent = tokens.joined()
        let toolCalls = extractToolCalls(content: fullContent, tools: request.tools)
        let finishReason = toolCalls != nil ? "tool_calls" : "stop"

        let message: ChatMessage
        if let toolCalls = toolCalls {
            message = ChatMessage(role: .assistant, toolCalls: toolCalls)
        } else {
            message = .assistant(fullContent)
        }

        return ChatCompletion(
            id: completionId,
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: modelName,
            choices: [
                ChatCompletion.Choice(
                    index: 0,
                    message: message,
                    finishReason: finishReason
                ),
            ],
            usage: ChatCompletion.Usage(
                promptTokens: estimateTokens(prompt),
                completionTokens: tokens.count,
                totalTokens: estimateTokens(prompt) + tokens.count
            )
        )
    }

    /// Convenience: create a completion from a single user message.
    public func create(_ message: String) async throws -> ChatCompletion {
        try await create(ChatRequest(messages: [.user(message)]))
    }

    // MARK: - Streaming

    /// Stream a chat completion, yielding chunks as they are generated.
    ///
    /// Equivalent to OpenAI's `client.chat.completions.create(stream: true)`.
    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        let completionId = "chatcmpl-\(UUID().uuidString.prefix(12))"
        let created = Int(Date().timeIntervalSince1970)
        let prompt = formatPrompt(request)
        let config = GenerateConfig(
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            topP: request.topP,
            stop: request.stop
        )
        let modelName = self.modelName
        let engine = self.engine
        let runtime = self.runtime

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var isFirst = true

                    if let runtime = runtime {
                        for try await token in runtime.generate(prompt: prompt, config: config) {
                            let chunk = Self.makeChunk(
                                id: completionId, created: created, model: modelName,
                                content: token, role: isFirst ? .assistant : nil
                            )
                            continuation.yield(chunk)
                            isFirst = false
                        }
                    } else {
                        for try await engineChunk in engine.generate(input: prompt, modality: .text) {
                            let text = String(data: engineChunk.data, encoding: .utf8) ?? ""
                            let chunk = Self.makeChunk(
                                id: completionId, created: created, model: modelName,
                                content: text, role: isFirst ? .assistant : nil
                            )
                            continuation.yield(chunk)
                            isFirst = false
                        }
                    }

                    // Final chunk with finish_reason
                    let finalChunk = ChatCompletionChunk(
                        id: completionId,
                        object: "chat.completion.chunk",
                        created: created,
                        model: modelName,
                        choices: [
                            ChatCompletionChunk.ChunkChoice(
                                index: 0,
                                delta: ChatCompletionChunk.Delta(),
                                finishReason: "stop"
                            ),
                        ]
                    )
                    continuation.yield(finalChunk)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience: stream a completion from a single user message.
    public func stream(_ message: String) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        stream(ChatRequest(messages: [.user(message)]))
    }

    // MARK: - Prompt formatting

    func formatPrompt(_ request: ChatRequest) -> String {
        var sb = ""

        if let tools = request.tools, !tools.isEmpty {
            sb += "<|system|>\nYou have access to the following tools:\n\n"
            for tool in tools {
                sb += "Function: \(tool.function.name)\n"
                sb += "Description: \(tool.function.description)\n"
                sb += "\n"
            }
            sb += "To use a tool, respond with JSON: {\"tool_call\": {\"name\": \"function_name\", \"arguments\": {...}}}\n\n"
        }

        for msg in request.messages {
            switch msg.role {
            case .system:    sb += "<|system|>\n\(msg.content ?? "")\n"
            case .user:      sb += "<|user|>\n\(msg.content ?? "")\n"
            case .assistant: sb += "<|assistant|>\n\(msg.content ?? "")\n"
            case .tool:      sb += "<|tool|>\n\(msg.content ?? "")\n"
            }
        }

        sb += "<|assistant|>\n"
        return sb
    }

    // MARK: - Tool call extraction

    private func extractToolCalls(content: String, tools: [Tool]?) -> [ToolCall]? {
        guard let tools = tools, !tools.isEmpty else { return nil }
        let toolNames = Set(tools.map { $0.function.name })

        guard let data = content.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolCallObj = json["tool_call"] as? [String: Any],
              let name = toolCallObj["name"] as? String,
              toolNames.contains(name) else {
            return nil
        }

        let arguments: String
        if let args = toolCallObj["arguments"] {
            if let argsData = try? JSONSerialization.data(withJSONObject: args) {
                arguments = String(data: argsData, encoding: .utf8) ?? "{}"
            } else {
                arguments = "{}"
            }
        } else {
            arguments = "{}"
        }

        return [
            ToolCall(
                id: "call_\(UUID().uuidString.prefix(8))",
                function: FunctionCall(name: name, arguments: arguments)
            ),
        ]
    }

    // MARK: - Helpers

    private func estimateTokens(_ text: String) -> Int {
        text.split(separator: " ").count
    }

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

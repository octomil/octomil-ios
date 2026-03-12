import Foundation

/// Cloud runtime that sends inference requests to an OpenAI-compatible
/// `/v1/chat/completions` endpoint via URLSession, with SSE streaming support.
public final class CloudModelRuntime: ModelRuntime, @unchecked Sendable {
    public let serverURL: String
    public let apiKey: String
    private let model: String
    private let session: URLSession

    /// - Parameters:
    ///   - serverURL: Base URL of the inference server (e.g. `https://api.octomil.com`).
    ///   - apiKey: Bearer token sent in the `Authorization` header.
    ///   - model: Model identifier sent in the request body (e.g. `gpt-4o-mini`).
    ///   - session: URLSession to use. Pass a custom session for testing.
    public init(
        serverURL: String = "https://api.octomil.com",
        apiKey: String,
        model: String = "gpt-4o-mini",
        session: URLSession? = nil
    ) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.model = model
        self.session = session ?? URLSession(configuration: .default)
    }

    public var capabilities: RuntimeCapabilities {
        RuntimeCapabilities(
            supportsToolCalls: true,
            supportsStructuredOutput: true,
            supportsStreaming: true
        )
    }

    // MARK: - Non-streaming

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        let urlRequest = try buildURLRequest(request: request, stream: false)
        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            throw CloudRuntimeError.invalidResponse("Missing choices array")
        }

        let message = firstChoice["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let finishReason = firstChoice["finish_reason"] as? String ?? "stop"

        // Parse tool calls if present
        var toolCalls: [RuntimeToolCall]?
        if let rawToolCalls = message?["tool_calls"] as? [[String: Any]] {
            toolCalls = rawToolCalls.compactMap { tc in
                guard let id = tc["id"] as? String,
                      let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let arguments = function["arguments"] as? String else {
                    return nil
                }
                return RuntimeToolCall(id: id, name: name, arguments: arguments)
            }
        }

        // Parse usage if present
        var usage: RuntimeUsage?
        if let usageJSON = json?["usage"] as? [String: Any] {
            let prompt = usageJSON["prompt_tokens"] as? Int ?? 0
            let completion = usageJSON["completion_tokens"] as? Int ?? 0
            let total = usageJSON["total_tokens"] as? Int ?? (prompt + completion)
            usage = RuntimeUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
        }

        return RuntimeResponse(
            text: text,
            toolCalls: toolCalls,
            finishReason: finishReason,
            usage: usage
        )
    }

    // MARK: - Streaming

    public func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { [self] continuation in
            let task = Task {
                do {
                    let urlRequest = try buildURLRequest(request: request, stream: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try validateHTTPResponse(response)

                    var buffer = ""
                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))
                        if char == "\n" {
                            let line = buffer
                            buffer = ""
                            guard let chunk = parseSseLine(line) else { continue }
                            continuation.yield(chunk)
                        } else {
                            buffer.append(char)
                        }
                    }
                    // Handle any remaining buffered line (server may not send trailing newline)
                    if !buffer.isEmpty, let chunk = parseSseLine(buffer) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func close() {
        session.invalidateAndCancel()
    }

    // MARK: - Private

    private func buildURLRequest(request: RuntimeRequest, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(serverURL)/v1/chat/completions") else {
            throw CloudRuntimeError.invalidURL(serverURL)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": request.prompt]],
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "stream": stream,
        ]

        if let stop = request.stop, !stop.isEmpty {
            body["stop"] = stop
        }

        // Include tool definitions if present
        if let toolDefs = request.toolDefinitions, !toolDefs.isEmpty {
            body["tools"] = toolDefs.map { tool -> [String: Any] in
                var function: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                ]
                if let schema = tool.parametersSchema {
                    // parametersSchema is a JSON string; parse it into a dict for the body
                    if let schemaData = schema.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: schemaData) {
                        function["parameters"] = parsed
                    }
                }
                return ["type": "function", "function": function]
            }
        }

        // Include JSON schema response format if present
        if let jsonSchema = request.jsonSchema {
            if jsonSchema == "{}" {
                body["response_format"] = ["type": "json_object"]
            } else {
                body["response_format"] = [
                    "type": "json_schema",
                    "json_schema": ["name": "response", "schema": jsonSchema],
                ]
            }
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudRuntimeError.invalidResponse("Not an HTTP response")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw CloudRuntimeError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Parse a single SSE line. Returns `nil` for non-data lines and `[DONE]`.
    private func parseSseLine(_ line: String) -> RuntimeChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data: ") else { return nil }
        let payload = String(trimmed.dropFirst(6))
        guard payload != "[DONE]" else { return nil }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        let delta = firstChoice["delta"] as? [String: Any]
        let text = delta?["content"] as? String
        let finishReason = firstChoice["finish_reason"] as? String

        // Parse streaming tool call deltas
        var toolCallDelta: RuntimeToolCallDelta?
        if let toolCalls = delta?["tool_calls"] as? [[String: Any]],
           let tc = toolCalls.first {
            let index = tc["index"] as? Int ?? 0
            let id = tc["id"] as? String
            let function = tc["function"] as? [String: Any]
            let name = function?["name"] as? String
            let argumentsDelta = function?["arguments"] as? String
            toolCallDelta = RuntimeToolCallDelta(
                index: index, id: id, name: name, argumentsDelta: argumentsDelta
            )
        }

        // Parse usage from the final chunk
        var usage: RuntimeUsage?
        if let usageJSON = json["usage"] as? [String: Any] {
            let prompt = usageJSON["prompt_tokens"] as? Int ?? 0
            let completion = usageJSON["completion_tokens"] as? Int ?? 0
            let total = usageJSON["total_tokens"] as? Int ?? (prompt + completion)
            usage = RuntimeUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
        }

        // Skip chunks with no meaningful content
        if text == nil && toolCallDelta == nil && finishReason == nil && usage == nil {
            return nil
        }

        return RuntimeChunk(
            text: text,
            toolCallDelta: toolCallDelta,
            finishReason: finishReason,
            usage: usage
        )
    }
}

// MARK: - Errors

/// Errors specific to ``CloudModelRuntime``.
public enum CloudRuntimeError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse(String)
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid server URL: \(url)"
        case .invalidResponse(let detail):
            return "Invalid cloud response: \(detail)"
        case .httpError(let code):
            return "HTTP error \(code)"
        }
    }
}

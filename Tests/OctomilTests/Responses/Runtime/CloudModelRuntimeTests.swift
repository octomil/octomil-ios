import XCTest
@testable import Octomil

final class CloudModelRuntimeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CloudMockURLProtocol.reset()
    }

    override func tearDown() {
        CloudMockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRuntime(
        serverURL: String = "https://test.octomil.com",
        apiKey: String = "test-key",
        model: String = "gpt-4o-mini"
    ) -> CloudModelRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return CloudModelRuntime(
            serverURL: serverURL,
            apiKey: apiKey,
            model: model,
            session: session
        )
    }

    // MARK: - Non-streaming tests

    func testRunSendsCorrectRequest() async throws {
        CloudMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            // Verify body
            let body = try Self.parseRequestBody(request)
            XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["max_tokens"] as? Int, 100)
            XCTAssertEqual(body["temperature"] as? Double, 0.5)

            let messages = body["messages"] as? [[String: Any]]
            XCTAssertEqual(messages?.first?["role"] as? String, "user")
            XCTAssertEqual(messages?.first?["content"] as? String, "Hello")

            return Self.jsonResponse(statusCode: 200, json: [
                "choices": [["message": ["content": "Hi there"], "finish_reason": "stop"]],
                "usage": ["prompt_tokens": 5, "completion_tokens": 2, "total_tokens": 7],
            ])
        }

        let runtime = makeRuntime()
        let response = try await runtime.run(request: RuntimeRequest(
            prompt: "Hello", maxTokens: 100, temperature: 0.5
        ))

        XCTAssertEqual(response.text, "Hi there")
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertEqual(response.usage?.promptTokens, 5)
        XCTAssertEqual(response.usage?.completionTokens, 2)
        XCTAssertEqual(response.usage?.totalTokens, 7)
    }

    func testRunParsesToolCalls() async throws {
        CloudMockURLProtocol.handler = { _ in
            Self.jsonResponse(statusCode: 200, json: [
                "choices": [[
                    "message": [
                        "content": "",
                        "tool_calls": [[
                            "id": "call_123",
                            "type": "function",
                            "function": [
                                "name": "get_weather",
                                "arguments": "{\"city\":\"NYC\"}",
                            ],
                        ]],
                    ],
                    "finish_reason": "tool_calls",
                ]],
                "usage": ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15],
            ])
        }

        let runtime = makeRuntime()
        let response = try await runtime.run(request: RuntimeRequest(prompt: "What's the weather?"))

        XCTAssertEqual(response.text, "")
        XCTAssertEqual(response.finishReason, "tool_calls")
        XCTAssertEqual(response.toolCalls?.count, 1)
        XCTAssertEqual(response.toolCalls?.first?.id, "call_123")
        XCTAssertEqual(response.toolCalls?.first?.name, "get_weather")
        XCTAssertEqual(response.toolCalls?.first?.arguments, "{\"city\":\"NYC\"}")
    }

    func testRunThrowsOnHTTPError() async {
        CloudMockURLProtocol.handler = { _ in
            Self.jsonResponse(statusCode: 429, json: ["error": ["message": "Rate limited"]])
        }

        let runtime = makeRuntime()
        do {
            _ = try await runtime.run(request: RuntimeRequest(prompt: "test"))
            XCTFail("Expected error to be thrown")
        } catch let error as CloudRuntimeError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 429)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRunThrowsOnMissingChoices() async {
        CloudMockURLProtocol.handler = { _ in
            Self.jsonResponse(statusCode: 200, json: ["id": "chatcmpl-abc"])
        }

        let runtime = makeRuntime()
        do {
            _ = try await runtime.run(request: RuntimeRequest(prompt: "test"))
            XCTFail("Expected error to be thrown")
        } catch let error as CloudRuntimeError {
            if case .invalidResponse = error {
                // expected
            } else {
                XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRunIncludesStopSequences() async throws {
        CloudMockURLProtocol.handler = { request in
            let body = try Self.parseRequestBody(request)
            XCTAssertEqual(body["stop"] as? [String], ["END", "STOP"])
            return Self.jsonResponse(statusCode: 200, json: [
                "choices": [["message": ["content": "ok"], "finish_reason": "stop"]],
            ])
        }

        let runtime = makeRuntime()
        _ = try await runtime.run(request: RuntimeRequest(
            prompt: "test", stop: ["END", "STOP"]
        ))
    }

    // MARK: - Streaming tests

    func testStreamParsesSSEChunks() async throws {
        let ssePayload = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"index\":0}]}",
            "",
            "data: {\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":2,\"total_tokens\":5}}",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")

        CloudMockURLProtocol.handler = { request in
            let body = try Self.parseRequestBody(request)
            XCTAssertEqual(body["stream"] as? Bool, true)
            return Self.sseResponse(statusCode: 200, body: ssePayload)
        }

        let runtime = makeRuntime()
        var texts: [String] = []
        var lastFinishReason: String?
        var lastUsage: RuntimeUsage?

        for try await chunk in runtime.stream(request: RuntimeRequest(prompt: "Hi")) {
            if let text = chunk.text { texts.append(text) }
            if let reason = chunk.finishReason { lastFinishReason = reason }
            if let usage = chunk.usage { lastUsage = usage }
        }

        XCTAssertEqual(texts, ["Hello", " world"])
        XCTAssertEqual(lastFinishReason, "stop")
        XCTAssertEqual(lastUsage?.promptTokens, 3)
        XCTAssertEqual(lastUsage?.completionTokens, 2)
        XCTAssertEqual(lastUsage?.totalTokens, 5)
    }

    func testStreamParsesToolCallDeltas() async throws {
        let ssePayload = [
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_abc\",\"function\":{\"name\":\"search\",\"arguments\":\"\"}}]},\"index\":0}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"q\\\"\"}}]},\"index\":0}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\": \\\"test\\\"}\"}}]},\"index\":0}]}",
            "",
            "data: {\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"tool_calls\"}]}",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")

        CloudMockURLProtocol.handler = { _ in
            Self.sseResponse(statusCode: 200, body: ssePayload)
        }

        let runtime = makeRuntime()
        var toolCallDeltas: [RuntimeToolCallDelta] = []
        var lastFinishReason: String?

        for try await chunk in runtime.stream(request: RuntimeRequest(prompt: "search")) {
            if let delta = chunk.toolCallDelta { toolCallDeltas.append(delta) }
            if let reason = chunk.finishReason { lastFinishReason = reason }
        }

        XCTAssertEqual(toolCallDeltas.count, 3)
        XCTAssertEqual(toolCallDeltas[0].id, "call_abc")
        XCTAssertEqual(toolCallDeltas[0].name, "search")
        XCTAssertEqual(toolCallDeltas[1].argumentsDelta, "{\"q\"")
        XCTAssertEqual(toolCallDeltas[2].argumentsDelta, ": \"test\"}")
        XCTAssertEqual(lastFinishReason, "tool_calls")
    }

    func testStreamThrowsOnHTTPError() async {
        CloudMockURLProtocol.handler = { _ in
            Self.sseResponse(statusCode: 500, body: "Internal Server Error")
        }

        let runtime = makeRuntime()
        do {
            for try await _ in runtime.stream(request: RuntimeRequest(prompt: "test")) {
                XCTFail("Should not yield any chunks")
            }
            XCTFail("Expected error")
        } catch let error as CloudRuntimeError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Capabilities

    func testCapabilities() {
        let runtime = makeRuntime()
        XCTAssertTrue(runtime.capabilities.supportsToolCalls)
        XCTAssertTrue(runtime.capabilities.supportsStructuredOutput)
        XCTAssertTrue(runtime.capabilities.supportsStreaming)
    }

    // MARK: - Request body helpers

    func testToolDefinitionsIncludedInBody() async throws {
        CloudMockURLProtocol.handler = { request in
            let body = try Self.parseRequestBody(request)
            let tools = body["tools"] as? [[String: Any]]
            XCTAssertEqual(tools?.count, 1)
            let function = (tools?.first?["function"] as? [String: Any])
            XCTAssertEqual(function?["name"] as? String, "get_weather")
            XCTAssertEqual(function?["description"] as? String, "Get weather info")
            return Self.jsonResponse(statusCode: 200, json: [
                "choices": [["message": ["content": "Sunny"], "finish_reason": "stop"]],
            ])
        }

        let runtime = makeRuntime()
        let toolDefs = [RuntimeToolDef(
            name: "get_weather",
            description: "Get weather info",
            parametersSchema: "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}}}"
        )]
        _ = try await runtime.run(request: RuntimeRequest(
            prompt: "weather?", toolDefinitions: toolDefs
        ))
    }

    // MARK: - Helpers

    private static func parseRequestBody(_ request: URLRequest) throws -> [String: Any] {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read > 0 { data.append(buffer, count: read) } else { break }
            }
            stream.close()
            body = data
        }
        guard let bodyData = body else {
            throw NSError(domain: "Test", code: 0, userInfo: [NSLocalizedDescriptionKey: "No body"])
        }
        return try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
    }

    private static func jsonResponse(statusCode: Int, json: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: URL(string: "https://test.octomil.com/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    private static func sseResponse(statusCode: Int, body: String) -> (Data, HTTPURLResponse) {
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://test.octomil.com/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        return (data, response)
    }
}

// MARK: - Mock URLProtocol for cloud runtime tests

/// A mock URLProtocol that supports both JSON and SSE streaming responses.
/// Uses a closure-based handler for flexible per-test response configuration.
private final class CloudMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        handler = nil
    }
}

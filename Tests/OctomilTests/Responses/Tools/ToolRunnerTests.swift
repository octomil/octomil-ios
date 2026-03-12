import XCTest
@testable import Octomil

final class ToolRunnerTests: XCTestCase {

    func testReturnsImmediatelyWhenNoToolCalls() async throws {
        let runtime = SequentialRuntime(responses: [
            RuntimeResponse(text: "Hello world"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let executor = CountingExecutor()
        let runner = ToolRunner(responses: responses, executor: executor)

        let response = try await runner.run(
            ResponseRequest(model: "test", input: [.text("Hi")])
        )

        if case .text(let text) = response.output.first {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected text output")
        }
        XCTAssertEqual(executor.callCount, 0)
    }

    func testExecutesToolCallAndFeedsResultBack() async throws {
        let runtime = SequentialRuntime(responses: [
            RuntimeResponse(
                text: "",
                toolCalls: [RuntimeToolCall(id: "call_1", name: "get_weather", arguments: "{\"city\":\"NYC\"}")]
            ),
            RuntimeResponse(text: "It's 72\u{00B0}F in NYC"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let executor = MapExecutor(results: ["get_weather": "72\u{00B0}F, sunny"])
        let runner = ToolRunner(responses: responses, executor: executor)

        let response = try await runner.run(
            ResponseRequest(model: "test", input: [.text("What's the weather?")])
        )

        let texts = response.output.compactMap { item -> String? in
            if case .text(let text) = item { return text }
            return nil
        }
        XCTAssertEqual(texts.joined(), "It's 72\u{00B0}F in NYC")
    }

    func testRespectsMaxIterations() async throws {
        let runtime = AlwaysToolCallRuntime()
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let executor = CountingExecutor()
        let runner = ToolRunner(responses: responses, executor: executor, maxIterations: 3)

        _ = try await runner.run(
            ResponseRequest(model: "test", input: [.text("Loop")])
        )

        XCTAssertEqual(executor.callCount, 3)
    }

    func testHandlesToolExecutionError() async throws {
        let runtime = SequentialRuntime(responses: [
            RuntimeResponse(
                text: "",
                toolCalls: [RuntimeToolCall(id: "call_1", name: "failing_tool", arguments: "{}")]
            ),
            RuntimeResponse(text: "Sorry, that didn't work"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let executor = FailingExecutor()
        let runner = ToolRunner(responses: responses, executor: executor)

        let response = try await runner.run(
            ResponseRequest(model: "test", input: [.text("Try this")])
        )

        let texts = response.output.compactMap { item -> String? in
            if case .text(let text) = item { return text }
            return nil
        }
        XCTAssertEqual(texts.joined(), "Sorry, that didn't work")
    }
}

// MARK: - Test helpers

private final class CountingExecutor: ToolExecutor, @unchecked Sendable {
    var callCount = 0
    func execute(call: ResponseToolCall) async throws -> ToolResult {
        callCount += 1
        return ToolResult(toolCallId: call.id, content: "ok")
    }
}

private final class MapExecutor: ToolExecutor, @unchecked Sendable {
    let results: [String: String]
    init(results: [String: String]) { self.results = results }
    func execute(call: ResponseToolCall) async throws -> ToolResult {
        ToolResult(toolCallId: call.id, content: results[call.name] ?? "unknown")
    }
}

private final class FailingExecutor: ToolExecutor, @unchecked Sendable {
    func execute(call: ResponseToolCall) async throws -> ToolResult {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
    }
}

private final class SequentialRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    private var responses: [RuntimeResponse]
    private var index = 0

    init(responses: [RuntimeResponse]) { self.responses = responses }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        guard index < responses.count else { return RuntimeResponse(text: "") }
        let response = responses[index]
        index += 1
        return response
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class AlwaysToolCallRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        RuntimeResponse(
            text: "",
            toolCalls: [RuntimeToolCall(id: "call_\(UUID().uuidString.prefix(8))", name: "loop", arguments: "{}")]
        )
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

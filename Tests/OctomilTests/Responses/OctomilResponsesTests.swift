import XCTest
@testable import Octomil

final class OctomilResponsesTests: XCTestCase {

    func testCreateReturnsTextResponse() async throws {
        let runtime = MockModelRuntime(response: RuntimeResponse(text: "Hello world"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "test", input: [.text("Hi")])
        )

        XCTAssertEqual(response.output.count, 1)
        if case .text(let text) = response.output.first {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected text output")
        }
        XCTAssertEqual(response.finishReason, "stop")
    }

    func testCreateReturnsToolCallResponse() async throws {
        let runtime = MockModelRuntime(response: RuntimeResponse(
            text: "",
            toolCalls: [RuntimeToolCall(id: "call_1", name: "get_weather", arguments: "{\"city\":\"NYC\"}")]
        ))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "test", input: [.text("Weather?")])
        )

        let toolCalls = response.output.compactMap { item -> ResponseToolCall? in
            if case .toolCall(let call) = item { return call }
            return nil
        }
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].name, "get_weather")
        XCTAssertEqual(response.finishReason, "tool_calls")
    }

    func testStreamEmitsTextDeltasAndDone() async throws {
        let runtime = StreamingMockRuntime(chunks: [
            RuntimeChunk(text: "Hello"),
            RuntimeChunk(text: " world"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        var events: [ResponseStreamEvent] = []
        for try await event in responses.stream(
            ResponseRequest(model: "test", input: [.text("Hi")])
        ) {
            events.append(event)
        }

        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(textDeltas, ["Hello", " world"])

        let doneEvents = events.compactMap { event -> Response? in
            if case .done(let response) = event { return response }
            return nil
        }
        XCTAssertEqual(doneEvents.count, 1)
        XCTAssertEqual(doneEvents[0].finishReason, "stop")
    }

    func testCreateIncludesUsage() async throws {
        let runtime = MockModelRuntime(response: RuntimeResponse(
            text: "result",
            usage: RuntimeUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
        ))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "test", input: [.text("Hi")])
        )

        XCTAssertEqual(response.usage?.promptTokens, 10)
        XCTAssertEqual(response.usage?.completionTokens, 5)
        XCTAssertEqual(response.usage?.totalTokens, 15)
    }

    func testCreateThrowsWhenNoRuntime() async {
        let responses = OctomilResponses(runtimeResolver: { _ in nil })
        do {
            _ = try await responses.create(
                ResponseRequest(model: "unknown", input: [.text("Hi")])
            )
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is OctomilResponsesError)
        }
    }
}

// MARK: - Test helpers

private final class MockModelRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let response: RuntimeResponse

    init(response: RuntimeResponse) { self.response = response }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse { response }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class StreamingMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let chunks: [RuntimeChunk]

    init(chunks: [RuntimeChunk]) { self.chunks = chunks }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse { RuntimeResponse(text: "") }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
    func close() {}
}

import XCTest
@testable import Octomil

final class ResponsesIntegrationTests: XCTestCase {

    override func tearDown() {
        ModelRuntimeRegistry.shared.clear()
        super.tearDown()
    }

    // MARK: - Default Factory

    func testCreateWithRegisteredDefaultFactory() async throws {
        ModelRuntimeRegistry.shared.defaultFactory = { _ in
            IntegrationMockRuntime(response: RuntimeResponse(
                text: "factory output",
                usage: RuntimeUsage(promptTokens: 5, completionTokens: 2, totalTokens: 7)
            ))
        }

        let responses = OctomilResponses()
        let response = try await responses.create(
            ResponseRequest(model: "any-model", input: [.text("Hello")])
        )

        XCTAssertEqual(response.output.count, 1)
        if case .text(let text) = response.output.first {
            XCTAssertEqual(text, "factory output")
        } else {
            XCTFail("Expected text output")
        }
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertEqual(response.usage?.totalTokens, 7)
    }

    func testStreamWithRegisteredDefaultFactory() async throws {
        ModelRuntimeRegistry.shared.defaultFactory = { _ in
            IntegrationStreamingRuntime(chunks: [
                RuntimeChunk(text: "stream"),
                RuntimeChunk(text: "ed"),
            ])
        }

        let responses = OctomilResponses()
        var events: [ResponseStreamEvent] = []
        for try await event in responses.stream(
            ResponseRequest(model: "any-model", input: [.text("Hi")])
        ) {
            events.append(event)
        }

        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(textDeltas, ["stream", "ed"])

        let doneEvents = events.compactMap { event -> Response? in
            if case .done(let response) = event { return response }
            return nil
        }
        XCTAssertEqual(doneEvents.count, 1)
    }

    // MARK: - String Shorthand

    func testCreateWithStringShorthand() async throws {
        let runtime = CapturingIntegrationRuntime()
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        _ = try await responses.create(
            ResponseRequest(model: "test", input: "Hello world")
        )

        // The string shorthand should produce a prompt containing "Hello world"
        XCTAssertNotNil(runtime.capturedRequest)
        XCTAssertTrue(runtime.capturedRequest!.prompt.contains("Hello world"))
    }

    // MARK: - Instructions

    func testCreateWithInstructionsPrependsSystemMessage() async throws {
        let runtime = CapturingIntegrationRuntime()
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        _ = try await responses.create(
            ResponseRequest(
                model: "test",
                input: [.text("What is 2+2?")],
                instructions: "You are a math tutor."
            )
        )

        XCTAssertNotNil(runtime.capturedRequest)
        let prompt = runtime.capturedRequest!.prompt

        // The system message should appear before the user message
        let systemRange = prompt.range(of: "You are a math tutor.")
        let userRange = prompt.range(of: "What is 2+2?")
        XCTAssertNotNil(systemRange)
        XCTAssertNotNil(userRange)
        XCTAssertTrue(systemRange!.lowerBound < userRange!.lowerBound)
    }

    // MARK: - Previous Response ID

    func testCreateWithPreviousResponseIdChainsConversation() async throws {
        let runtime = IntegrationSequentialRuntime(responses: [
            RuntimeResponse(text: "I am a helpful assistant."),
            RuntimeResponse(text: "2+2 is 4."),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        // First request
        let first = try await responses.create(
            ResponseRequest(model: "test", input: [.text("Who are you?")])
        )
        XCTAssertEqual(first.output.count, 1)

        // Second request referencing the first
        let second = try await responses.create(
            ResponseRequest(
                model: "test",
                input: [.text("What is 2+2?")],
                previousResponseId: first.id
            )
        )

        if case .text(let text) = second.output.first {
            XCTAssertEqual(text, "2+2 is 4.")
        } else {
            XCTFail("Expected text output")
        }

        // Verify the runtime received a prompt that includes the previous assistant output
        XCTAssertNotNil(runtime.capturedPrompts.last)
        XCTAssertTrue(runtime.capturedPrompts.last!.contains("I am a helpful assistant."))
    }
}

// MARK: - Test Helpers

private final class IntegrationMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let response: RuntimeResponse

    init(response: RuntimeResponse) { self.response = response }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse { response }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class IntegrationStreamingRuntime: ModelRuntime, @unchecked Sendable {
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

private final class CapturingIntegrationRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    var capturedRequest: RuntimeRequest?

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        capturedRequest = request
        return RuntimeResponse(text: "ok")
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class IntegrationSequentialRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    private var responses: [RuntimeResponse]
    private var index = 0
    var capturedPrompts: [String] = []

    init(responses: [RuntimeResponse]) { self.responses = responses }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        capturedPrompts.append(request.prompt)
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

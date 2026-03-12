import XCTest
@testable import Octomil

final class LLMRuntimeAdapterTests: XCTestCase {

    func testRunCollectsAllTokens() async throws {
        let llm = MockLLMRuntime(tokens: ["Hello", " world"])
        let adapter = LLMRuntimeAdapter(llmRuntime: llm)

        let response = try await adapter.run(request: RuntimeRequest(prompt: "test"))

        XCTAssertEqual(response.text, "Hello world")
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertNotNil(response.usage)
        XCTAssertEqual(response.usage?.completionTokens, 2)
    }

    func testStreamEmitsChunks() async throws {
        let llm = MockLLMRuntime(tokens: ["a", "b", "c"])
        let adapter = LLMRuntimeAdapter(llmRuntime: llm)

        var chunks: [RuntimeChunk] = []
        for try await chunk in adapter.stream(request: RuntimeRequest(prompt: "test")) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].text, "a")
        XCTAssertEqual(chunks[1].text, "b")
        XCTAssertEqual(chunks[2].text, "c")
    }

    func testRunPassesConfig() async throws {
        let llm = CapturingLLMRuntime()
        let adapter = LLMRuntimeAdapter(llmRuntime: llm)

        _ = try await adapter.run(request: RuntimeRequest(
            prompt: "test", maxTokens: 100, temperature: 0.5, topP: 0.9, stop: ["END"]
        ))

        XCTAssertEqual(llm.capturedConfig?.maxTokens, 100)
        XCTAssertEqual(llm.capturedConfig?.temperature, 0.5)
        XCTAssertEqual(llm.capturedConfig?.topP, 0.9)
        XCTAssertEqual(llm.capturedConfig?.stop, ["END"])
    }

    func testCloseDelegatesToLLMRuntime() {
        let llm = MockLLMRuntime(tokens: [])
        let adapter = LLMRuntimeAdapter(llmRuntime: llm)
        adapter.close()
        XCTAssertTrue(llm.closed)
    }
}

// MARK: - Test helpers

private final class MockLLMRuntime: LLMRuntime, @unchecked Sendable {
    let tokens: [String]
    var closed = false

    init(tokens: [String]) { self.tokens = tokens }

    func generate(prompt: String, config: GenerateConfig) -> AsyncThrowingStream<String, Error> {
        let tokens = self.tokens
        return AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }

    func close() { closed = true }
}

private final class CapturingLLMRuntime: LLMRuntime, @unchecked Sendable {
    var capturedConfig: GenerateConfig?

    func generate(prompt: String, config: GenerateConfig) -> AsyncThrowingStream<String, Error> {
        capturedConfig = config
        return AsyncThrowingStream { continuation in
            continuation.yield("ok")
            continuation.finish()
        }
    }

    func close() {}
}

import XCTest
@testable import Octomil

final class RouterModelRuntimeTests: XCTestCase {

    func testAutoUsesLocalWhenAvailable() async throws {
        let localRuntime = RouterMockRuntime(text: "local result")
        let cloudRuntime = RouterMockRuntime(text: "cloud result")

        let router = RouterModelRuntime(
            localFactory: { _ in localRuntime },
            cloudFactory: { _ in cloudRuntime },
            defaultPolicy: .auto()
        )

        let response = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
        XCTAssertEqual(response.text, "local result")
    }

    func testAutoFallsBackToCloud() async throws {
        let cloudRuntime = RouterMockRuntime(text: "cloud result")

        let router = RouterModelRuntime(
            localFactory: nil,
            cloudFactory: { _ in cloudRuntime },
            defaultPolicy: .auto(fallback: "cloud")
        )

        let response = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
        XCTAssertEqual(response.text, "cloud result")
    }

    func testCloudFirstUsesCloudWhenAvailable() async throws {
        let localRuntime = RouterMockRuntime(text: "local result")
        let cloudRuntime = RouterMockRuntime(text: "cloud result")

        let router = RouterModelRuntime(
            localFactory: { _ in localRuntime },
            cloudFactory: { _ in cloudRuntime },
            defaultPolicy: .auto(preferLocal: false)
        )

        let response = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
        XCTAssertEqual(response.text, "cloud result")
    }

    func testCloudFirstFallsBackToLocal() async throws {
        let localRuntime = RouterMockRuntime(text: "local result")

        let router = RouterModelRuntime(
            localFactory: { _ in localRuntime },
            cloudFactory: nil,
            defaultPolicy: .auto(preferLocal: false)
        )

        let response = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
        XCTAssertEqual(response.text, "local result")
    }

    func testLocalOnlyThrowsWhenNoLocal() async {
        let router = RouterModelRuntime(
            localFactory: nil,
            cloudFactory: { _ in RouterMockRuntime(text: "cloud") },
            defaultPolicy: .localOnly
        )

        do {
            _ = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is OctomilResponsesError)
        }
    }

    func testCloudOnlyUsesCloud() async throws {
        let localRuntime = RouterMockRuntime(text: "local result")
        let cloudRuntime = RouterMockRuntime(text: "cloud result")

        let router = RouterModelRuntime(
            localFactory: { _ in localRuntime },
            cloudFactory: { _ in cloudRuntime },
            defaultPolicy: .cloudOnly
        )

        let response = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
        XCTAssertEqual(response.text, "cloud result")
    }

    func testFromMetadataParsesPolicy() {
        // local_only
        let localOnly = InferenceRoutingPolicy.fromMetadata(["routing.policy": "local_only"])
        if case .localOnly = localOnly {
            // pass
        } else {
            XCTFail("Expected localOnly, got \(String(describing: localOnly))")
        }

        // cloud_only
        let cloudOnly = InferenceRoutingPolicy.fromMetadata(["routing.policy": "cloud_only"])
        if case .cloudOnly = cloudOnly {
            // pass
        } else {
            XCTFail("Expected cloudOnly, got \(String(describing: cloudOnly))")
        }

        // auto with parameters
        let auto = InferenceRoutingPolicy.fromMetadata([
            "routing.policy": "auto",
            "routing.prefer_local": "false",
            "routing.max_latency_ms": "500",
            "routing.fallback": "none",
        ])
        if case .auto(let preferLocal, let maxLatencyMs, let fallback) = auto {
            XCTAssertFalse(preferLocal)
            XCTAssertEqual(maxLatencyMs, 500)
            XCTAssertEqual(fallback, "none")
        } else {
            XCTFail("Expected auto, got \(String(describing: auto))")
        }

        // nil metadata
        let nilPolicy = InferenceRoutingPolicy.fromMetadata(nil)
        XCTAssertNil(nilPolicy)

        // unknown policy
        let unknown = InferenceRoutingPolicy.fromMetadata(["routing.policy": "unknown"])
        XCTAssertNil(unknown)
    }

    func testAutoThrowsWhenNoRuntimeAvailable() async {
        let router = RouterModelRuntime(
            localFactory: nil,
            cloudFactory: nil,
            defaultPolicy: .auto()
        )

        do {
            _ = try await router.run(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])]))
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is OctomilResponsesError)
        }
    }

    func testStreamDelegatesToSelectedRuntime() async throws {
        let localRuntime = RouterStreamingMockRuntime(chunks: [
            RuntimeChunk(text: "streamed"),
        ])

        let router = RouterModelRuntime(
            localFactory: { _ in localRuntime },
            defaultPolicy: .auto()
        )

        var texts: [String] = []
        for try await chunk in router.stream(request: RuntimeRequest(messages: [RuntimeMessage(role: .user, parts: [.text("test")])])) {
            if let text = chunk.text { texts.append(text) }
        }
        XCTAssertEqual(texts, ["streamed"])
    }
}

// MARK: - Test Helpers

private final class RouterMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let text: String

    init(text: String) { self.text = text }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        RuntimeResponse(text: text)
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class RouterStreamingMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let chunks: [RuntimeChunk]

    init(chunks: [RuntimeChunk]) { self.chunks = chunks }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        RuntimeResponse(text: "")
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
    func close() {}
}

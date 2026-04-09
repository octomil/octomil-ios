import XCTest
@testable import Octomil

final class UnifiedFacadeTests: XCTestCase {

    // MARK: - Constructor tests

    func testInitWithPublishableKey() {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        // Should not throw — facade is created but not initialized
        XCTAssertNotNil(facade)
    }

    func testInitWithApiKeyAndOrgId() {
        let facade = Octomil(apiKey: "edg_abc123", orgId: "org_456")
        XCTAssertNotNil(facade)
    }

    // MARK: - Initialization

    func testInitializeIsIdempotent() async throws {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        try await facade.initialize()
        try await facade.initialize() // second call should not throw
        let _ = try facade.responses // should work after init
    }

    // MARK: - Not initialized guard

    func testResponsesBeforeInitializeThrows() {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        XCTAssertThrowsError(try facade.responses) { error in
            XCTAssertTrue(error is OctomilNotInitializedError)
        }
    }

    // MARK: - Response.outputText

    func testOutputTextConcatenatesTextItems() {
        let response = Response(
            id: "resp_1",
            model: "test-model",
            output: [.text("Hello"), .text(" world")],
            finishReason: "stop"
        )
        XCTAssertEqual(response.outputText, "Hello world")
    }

    func testOutputTextReturnsEmptyForEmptyOutput() {
        let response = Response(
            id: "resp_2",
            model: "test-model",
            output: [],
            finishReason: "stop"
        )
        XCTAssertEqual(response.outputText, "")
    }

    func testOutputTextSkipsNonTextItems() {
        let toolCall = ResponseToolCall(id: "tc_1", name: "search", arguments: "{}")
        let response = Response(
            id: "resp_3",
            model: "test-model",
            output: [.text("before"), .toolCall(toolCall), .text("after")],
            finishReason: "stop"
        )
        XCTAssertEqual(response.outputText, "beforeafter")
    }

    // MARK: - Embeddings namespace

    func testEmbeddingsBeforeInitializeThrows() {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        XCTAssertThrowsError(try facade.embeddings) { error in
            XCTAssertTrue(error is OctomilNotInitializedError)
        }
    }

    func testEmbeddingsNamespaceExistsAfterInitialize() async throws {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        try await facade.initialize()
        let emb = try facade.embeddings
        XCTAssertNotNil(emb)
    }

    func testEmbeddingsNamespaceType() async throws {
        let facade = Octomil(apiKey: "edg_abc123", orgId: "org_456")
        try await facade.initialize()
        let emb = try facade.embeddings
        XCTAssertTrue(emb is FacadeEmbeddings)
    }

    func testEmbeddingsIdempotentInitialize() async throws {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        try await facade.initialize()
        try await facade.initialize() // second call should be a no-op
        let emb = try facade.embeddings
        XCTAssertNotNil(emb)
    }

    func testPublishableKeyEmbeddingsCreateThrowsNetworkError() async throws {
        let facade = Octomil(publishableKey: "oct_pub_test_abc123")
        try await facade.initialize()

        let emb = try facade.embeddings
        XCTAssertTrue(emb is FacadeEmbeddings)

        // Calling create against the default server URL (no server running) should
        // fail with a network-level error (URLError), NOT an auth or init error.
        // This proves the publishable key was wired through to the EmbeddingClient.
        do {
            _ = try await emb.create(model: "test-model", input: "hello")
            XCTFail("Expected network error but call succeeded")
        } catch is OctomilNotInitializedError {
            XCTFail("Got OctomilNotInitializedError — auth was not wired through")
        } catch let error as URLError {
            // Expected: network error because no server is running
            XCTAssertTrue(
                [.cannotConnectToHost, .networkConnectionLost, .timedOut, .notConnectedToInternet,
                 .cannotFindHost, .secureConnectionFailed].contains(error.code),
                "Unexpected URLError code: \(error.code)"
            )
        } catch let error as OctomilError {
            // Also acceptable: server error from a reachable host returning an error status
            switch error {
            case .serverError:
                break // This is fine — the request reached the network layer
            default:
                XCTFail("Unexpected OctomilError: \(error)")
            }
        }
    }
}

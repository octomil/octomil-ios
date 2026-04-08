import XCTest
@testable import Octomil

final class UnifiedFacadeTests: XCTestCase {

    // MARK: - Constructor tests

    func testInitWithPublishableKey() {
        let facade = OctomilSDK(publishableKey: "oct_pub_test_abc123")
        // Should not throw — facade is created but not initialized
        XCTAssertNotNil(facade)
    }

    func testInitWithApiKeyAndOrgId() {
        let facade = OctomilSDK(apiKey: "edg_abc123", orgId: "org_456")
        XCTAssertNotNil(facade)
    }

    // MARK: - Initialization

    func testInitializeIsIdempotent() async throws {
        let facade = OctomilSDK(publishableKey: "oct_pub_test_abc123")
        try await facade.initialize()
        try await facade.initialize() // second call should not throw
        let _ = try facade.responses // should work after init
    }

    // MARK: - Not initialized guard

    func testResponsesBeforeInitializeThrows() {
        let facade = OctomilSDK(publishableKey: "oct_pub_test_abc123")
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
}

import XCTest
@testable import Octomil

final class CloudStreamingInferenceTests: XCTestCase {

    // MARK: - StreamToken

    func testStreamTokenDefaults() {
        let token = StreamToken(
            token: "hello",
            done: false,
            provider: nil,
            latencyMs: nil,
            sessionId: nil
        )
        XCTAssertEqual(token.token, "hello")
        XCTAssertFalse(token.done)
        XCTAssertNil(token.provider)
        XCTAssertNil(token.latencyMs)
        XCTAssertNil(token.sessionId)
    }

    func testStreamTokenAllFields() {
        let token = StreamToken(
            token: "world",
            done: true,
            provider: "ollama",
            latencyMs: 42.5,
            sessionId: "abc-123"
        )
        XCTAssertEqual(token.token, "world")
        XCTAssertTrue(token.done)
        XCTAssertEqual(token.provider, "ollama")
        XCTAssertEqual(token.latencyMs, 42.5)
        XCTAssertEqual(token.sessionId, "abc-123")
    }

    func testStreamTokenEquatable() {
        let a = StreamToken(token: "x", done: false, provider: nil, latencyMs: nil, sessionId: nil)
        let b = StreamToken(token: "x", done: false, provider: nil, latencyMs: nil, sessionId: nil)
        let c = StreamToken(token: "y", done: false, provider: nil, latencyMs: nil, sessionId: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - SSE Parsing

    func testParseSSELineNormalToken() {
        let line = #"data: {"token": "The", "done": false, "provider": "ollama"}"#
        let token = CloudStreamingClient.parseSSELine(line)
        XCTAssertNotNil(token)
        XCTAssertEqual(token?.token, "The")
        XCTAssertFalse(token!.done)
        XCTAssertEqual(token?.provider, "ollama")
    }

    func testParseSSELineDoneToken() {
        let line = #"data: {"done": true, "latency_ms": 1234.5, "session_id": "abc-123"}"#
        let token = CloudStreamingClient.parseSSELine(line)
        XCTAssertNotNil(token)
        XCTAssertTrue(token!.done)
        XCTAssertEqual(token?.token, "")
        XCTAssertEqual(token?.latencyMs, 1234.5)
        XCTAssertEqual(token?.sessionId, "abc-123")
    }

    func testParseSSELineEmptyLineReturnsNil() {
        XCTAssertNil(CloudStreamingClient.parseSSELine(""))
        XCTAssertNil(CloudStreamingClient.parseSSELine("   "))
    }

    func testParseSSELineNonDataReturnsNil() {
        XCTAssertNil(CloudStreamingClient.parseSSELine("event: message"))
        XCTAssertNil(CloudStreamingClient.parseSSELine("id: 1"))
        XCTAssertNil(CloudStreamingClient.parseSSELine(": comment"))
    }

    func testParseSSELineEmptyDataReturnsNil() {
        XCTAssertNil(CloudStreamingClient.parseSSELine("data:"))
        XCTAssertNil(CloudStreamingClient.parseSSELine("data:   "))
    }

    func testParseSSELineInvalidJSONReturnsNil() {
        XCTAssertNil(CloudStreamingClient.parseSSELine("data: not-json"))
    }

    func testParseSSELineWithWhitespace() {
        let line = #"  data: {"token": "x", "done": false}  "#
        let token = CloudStreamingClient.parseSSELine(line)
        XCTAssertNotNil(token)
        XCTAssertEqual(token?.token, "x")
    }
}

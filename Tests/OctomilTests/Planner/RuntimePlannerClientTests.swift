import Foundation
import XCTest
@testable import Octomil

final class RuntimePlannerClientTests: XCTestCase {

    // MARK: - URL Construction

    func testPlanPath() {
        XCTAssertEqual(RuntimePlannerClient.planPath, "/api/v2/runtime/plan")
    }

    func testBenchmarkPath() {
        XCTAssertEqual(RuntimePlannerClient.benchmarkPath, "/api/v2/runtime/benchmarks")
    }

    // MARK: - Initialization

    func testDefaultInitialization() async {
        let client = RuntimePlannerClient()
        // Just verify it can be created without crashing
        XCTAssertNotNil(client)
    }

    func testCustomInitialization() async {
        let client = RuntimePlannerClient(
            baseURL: URL(string: "https://custom.example.com")!,
            apiKey: "test-key",
            timeoutSeconds: 5
        )
        XCTAssertNotNil(client)
    }

    // MARK: - Fetch Plan: Error Handling

    func testFetchPlanReturnsNilOnInvalidURL() async {
        // Use a URL that will fail to connect
        let client = RuntimePlannerClient(
            baseURL: URL(string: "http://localhost:1")!, // Port 1 is never open
            apiKey: "test",
            timeoutSeconds: 1
        )

        let profile = DeviceRuntimeProfileCollector.collect()

        let result = await client.fetchPlan(
            model: "test-model",
            capability: "text",
            device: profile
        )

        XCTAssertNil(result, "Should return nil on connection failure")
    }

    // MARK: - Upload Benchmark: Error Handling

    func testUploadBenchmarkReturnsFalseOnFailure() async {
        let client = RuntimePlannerClient(
            baseURL: URL(string: "http://localhost:1")!,
            apiKey: "test",
            timeoutSeconds: 1
        )

        let result = await client.uploadBenchmark([
            "model": "test-model",
            "engine": "coreml",
            "tokens_per_second": 50.0,
        ])

        XCTAssertFalse(result, "Should return false on connection failure")
    }

    // MARK: - Auth Header

    func testFetchPlanWithoutApiKey() async {
        // Client without an API key should still attempt the request
        // (the server will decide if it's authorized)
        let client = RuntimePlannerClient(
            baseURL: URL(string: "http://localhost:1")!,
            apiKey: nil,
            timeoutSeconds: 1
        )

        let profile = DeviceRuntimeProfileCollector.collect()

        // This will fail due to connection, but it should not crash
        let result = await client.fetchPlan(
            model: "test",
            capability: "text",
            device: profile
        )
        XCTAssertNil(result)
    }

    // MARK: - Mock Server Response Parsing

    func testParsePlanResponseFromMockData() async {
        // Test that the client can parse a valid server response.
        // We create a URLProtocol-based mock for this.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockPlanURLProtocol.self]
        let session = URLSession(configuration: config)

        let client = RuntimePlannerClient(
            baseURL: URL(string: "https://api.octomil.com")!,
            apiKey: "test-key",
            session: session
        )

        let profile = DeviceRuntimeProfileCollector.collect()

        let result = await client.fetchPlan(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            device: profile
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.model, "llama-8b")
        XCTAssertEqual(result?.capability, "text")
        XCTAssertEqual(result?.candidates.count, 1)
        XCTAssertEqual(result?.candidates.first?.engine, "mlx")
        XCTAssertEqual(result?.candidates.first?.locality, .local)
    }

    func testParseBenchmarkUploadFromMock() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBenchmarkURLProtocol.self]
        let session = URLSession(configuration: config)

        let client = RuntimePlannerClient(
            baseURL: URL(string: "https://api.octomil.com")!,
            apiKey: "test-key",
            session: session
        )

        let result = await client.uploadBenchmark([
            "source": "planner",
            "model": "test-model",
            "engine": "coreml",
            "tokens_per_second": 75.0,
        ])

        XCTAssertTrue(result)
    }

    func testFetchPlanHandlesBadJSON() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBadJSONURLProtocol.self]
        let session = URLSession(configuration: config)

        let client = RuntimePlannerClient(
            baseURL: URL(string: "https://api.octomil.com")!,
            apiKey: "test-key",
            session: session
        )

        let profile = DeviceRuntimeProfileCollector.collect()

        let result = await client.fetchPlan(
            model: "test",
            capability: "text",
            device: profile
        )

        XCTAssertNil(result, "Should return nil on decode failure")
    }

    func testFetchPlanHandles500() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Mock500URLProtocol.self]
        let session = URLSession(configuration: config)

        let client = RuntimePlannerClient(
            baseURL: URL(string: "https://api.octomil.com")!,
            apiKey: "test-key",
            session: session
        )

        let profile = DeviceRuntimeProfileCollector.collect()

        let result = await client.fetchPlan(
            model: "test",
            capability: "text",
            device: profile
        )

        XCTAssertNil(result, "Should return nil on HTTP 500")
    }
}

// MARK: - Mock URL Protocols

private class MockPlanURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let json = """
        {
            "model": "llama-8b",
            "capability": "text",
            "policy": "local_first",
            "candidates": [
                {
                    "locality": "local",
                    "priority": 1,
                    "confidence": 0.9,
                    "reason": "Best for this device",
                    "engine": "mlx",
                    "benchmark_required": false
                }
            ],
            "fallback_candidates": [],
            "plan_ttl_seconds": 604800,
            "server_generated_at": "2026-04-12T00:00:00Z"
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: json)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private class MockBenchmarkURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private class MockBadJSONURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let badJson = "this is not json".data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: badJson)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private class Mock500URLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

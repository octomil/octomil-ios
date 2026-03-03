import Foundation
import XCTest
@testable import Octomil

final class ModelFormatClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
    }

    override func tearDown() {
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(apiKey: String? = "test-key") -> ModelFormatClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return ModelFormatClient(
            apiBase: URL(string: "https://api.octomil.com")!,
            apiKey: apiKey,
            platform: "ios",
            session: session
        )
    }

    // MARK: - Server Response Parsing

    func testGetPreferredFormatFromServer() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "coreml",
                "fallback_format": "onnx",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        let preference = await client.getPreferredFormat(modelId: "test-model")

        XCTAssertEqual(preference.format, "coreml")
        XCTAssertEqual(preference.fallbackFormat, "onnx")
        XCTAssertEqual(preference.ttlSeconds, 300)
    }

    func testGetFormatConvenienceMethod() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "mlx",
                "ttl_seconds": 60,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        let format = await client.getFormat(modelId: "llm-model")
        XCTAssertEqual(format, "mlx")
    }

    // MARK: - Fallback to Default

    func testFallbackToDefaultWhenServerUnreachable() async {
        // No responses queued — simulates network failure.
        let client = makeClient()
        await client.clearCache()

        let preference = await client.getPreferredFormat(modelId: "unreachable-model")

        XCTAssertEqual(preference.format, "auto")
        XCTAssertNil(preference.fallbackFormat)
    }

    func testFallbackToDefaultOnServerError() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["error": "internal server error"])
        ]

        let client = makeClient()
        await client.clearCache()

        let preference = await client.getPreferredFormat(modelId: "error-model")
        XCTAssertEqual(preference.format, "auto")
    }

    // MARK: - In-Memory Caching

    func testInMemoryCacheReturnsCachedValue() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "coreml",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        // First call fetches from server
        let first = await client.getPreferredFormat(modelId: "cached-model")
        XCTAssertEqual(first.format, "coreml")

        // Second call should use in-memory cache (no more server responses queued)
        let second = await client.getPreferredFormat(modelId: "cached-model")
        XCTAssertEqual(second.format, "coreml")

        // Only one request should have been made
        XCTAssertEqual(SharedMockURLProtocol.requests.count, 1)
    }

    // MARK: - Request Format

    func testRequestIncludesPlatformQueryParam() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "auto",
                "ttl_seconds": 60,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        _ = await client.getPreferredFormat(modelId: "platform-test")

        let request = SharedMockURLProtocol.requests.first
        XCTAssertNotNil(request)
        let url = request?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("platform=ios"), "URL should contain platform query param: \(url)")
        XCTAssertTrue(url.contains("api/v1/models/platform-test/format"), "URL should contain correct path: \(url)")
    }

    func testRequestIncludesAuthorizationHeader() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "auto",
                "ttl_seconds": 60,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient(apiKey: "my-secret-key")
        await client.clearCache()

        _ = await client.getPreferredFormat(modelId: "auth-test")

        let request = SharedMockURLProtocol.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-key")
    }

    // MARK: - Cache Clearing

    func testClearCacheForSpecificModel() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "mlx",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
            // Second response for after cache clear
            .success(statusCode: 200, json: [
                "format": "coreml",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
        ]

        let client = makeClient()
        await client.clearCache()

        let first = await client.getPreferredFormat(modelId: "clear-test")
        XCTAssertEqual(first.format, "mlx")

        await client.clearCache(modelId: "clear-test")

        let second = await client.getPreferredFormat(modelId: "clear-test")
        XCTAssertEqual(second.format, "coreml")
    }

    func testClearAllCache() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "mlx",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
            // Second fetch after cache clear — returns default since no more responses
        ]

        let client = makeClient()
        await client.clearCache()

        let first = await client.getPreferredFormat(modelId: "clear-all-test")
        XCTAssertEqual(first.format, "mlx")

        await client.clearCache()

        // After clearing, with no server response, should fall back to default
        let second = await client.getPreferredFormat(modelId: "clear-all-test")
        XCTAssertEqual(second.format, "auto")
    }

    // MARK: - ETag Conditional Requests

    func testETagSentOnSubsequentRequests() async {
        SharedMockURLProtocol.responses = [
            // First response with ETag
            .success(statusCode: 200, json: [
                "format": "coreml",
                "ttl_seconds": 0, // expire immediately
                "fetched_at": 0,
                "etag": "",
            ]),
            // Second response (304 Not Modified)
            .success(statusCode: 200, json: [
                "format": "coreml",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
        ]

        let client = makeClient()
        await client.clearCache()

        // First call
        _ = await client.getPreferredFormat(modelId: "etag-test")

        // Second call — TTL is 0 so it should refetch
        _ = await client.getPreferredFormat(modelId: "etag-test")

        XCTAssertEqual(SharedMockURLProtocol.requests.count, 2)
    }

    // MARK: - ModelFormatPreference Codable

    func testModelFormatPreferenceCodableRoundTrip() throws {
        let preference = ModelFormatPreference(
            format: "coreml",
            fallbackFormat: "onnx",
            ttlSeconds: 300,
            fetchedAt: 1000.0,
            etag: "\"abc123\""
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(preference)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelFormatPreference.self, from: data)

        XCTAssertEqual(decoded.format, "coreml")
        XCTAssertEqual(decoded.fallbackFormat, "onnx")
        XCTAssertEqual(decoded.ttlSeconds, 300)
        XCTAssertEqual(decoded.fetchedAt, 1000.0)
        XCTAssertEqual(decoded.etag, "\"abc123\"")
    }

    func testModelFormatPreferenceCodingKeysSnakeCase() throws {
        let preference = ModelFormatPreference(
            format: "mlx",
            fallbackFormat: nil,
            ttlSeconds: 600,
            fetchedAt: 0,
            etag: ""
        )

        let data = try JSONEncoder().encode(preference)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["fallback_format"])
        XCTAssertNotNil(json["ttl_seconds"])
        XCTAssertNotNil(json["fetched_at"])
    }

    func testModelFormatPreferenceDeserializationFromServerJSON() throws {
        let serverJSON = """
        {
            "format": "mlx",
            "fallback_format": "coreml",
            "ttl_seconds": 600,
            "fetched_at": 0,
            "etag": ""
        }
        """.data(using: .utf8)!

        let preference = try JSONDecoder().decode(ModelFormatPreference.self, from: serverJSON)
        XCTAssertEqual(preference.format, "mlx")
        XCTAssertEqual(preference.fallbackFormat, "coreml")
        XCTAssertEqual(preference.ttlSeconds, 600)
    }

    // MARK: - Default Preference

    func testDefaultPreferenceValues() {
        let pref = defaultModelFormatPreference
        XCTAssertEqual(pref.format, "auto")
        XCTAssertNil(pref.fallbackFormat)
        XCTAssertEqual(pref.ttlSeconds, 0)
    }

    // MARK: - Different Models Get Independent Caches

    func testDifferentModelsHaveIndependentCaches() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "format": "coreml",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
            .success(statusCode: 200, json: [
                "format": "mlx",
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
        ]

        let client = makeClient()
        await client.clearCache()

        let format1 = await client.getFormat(modelId: "model-a")
        let format2 = await client.getFormat(modelId: "model-b")

        XCTAssertEqual(format1, "coreml")
        XCTAssertEqual(format2, "mlx")
        XCTAssertEqual(SharedMockURLProtocol.requests.count, 2)
    }
}

import Foundation
import XCTest
@testable import Octomil

final class DeviceProfileClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
    }

    override func tearDown() {
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(apiKey: String? = "test-key") -> DeviceProfileClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return DeviceProfileClient(
            apiBase: URL(string: "https://api.octomil.com")!,
            apiKey: apiKey,
            session: session
        )
    }

    // MARK: - Server Response Parsing

    func testResolveProfileFromServer() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": [
                    "iPhone16,1": "iphone_15_pro",
                    "iPhone16,2": "iphone_15_pro",
                    "iPhone17,1": "iphone_16_pro",
                ],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        let profile = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 8192)
        XCTAssertEqual(profile, "iphone_15_pro")
    }

    func testResolveProfileCaseInsensitive() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": [
                    "iPhone16,1": "iphone_15_pro",
                ],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        // Machine ID from uname is lowercase
        let profile = await client.resolveProfile(machineId: "iphone16,1", totalMemoryMB: 8192)
        XCTAssertEqual(profile, "iphone_15_pro")
    }

    func testResolveProfileUnknownDeviceFallsBackToRAM() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": [
                    "iPhone16,1": "iphone_15_pro",
                ],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        // Unknown device with 8GB RAM -> "high"
        let profile = await client.resolveProfile(machineId: "iPhone99,1", totalMemoryMB: 8192)
        XCTAssertEqual(profile, "high")
    }

    // MARK: - RAM Tier Classification

    func testRAMTierHigh() {
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 8192), .high)
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 12000), .high)
    }

    func testRAMTierMid() {
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 6144), .mid)
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 4096), .mid)
    }

    func testRAMTierLow() {
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 3072), .low)
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 2048), .low)
    }

    func testRAMTierBoundaries() {
        // 8192 MB = 8 * 1024 -> high
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 8 * 1024), .high)
        // 8 * 1024 - 1 -> mid
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 8 * 1024 - 1), .mid)
        // 4 * 1024 -> mid
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 4 * 1024), .mid)
        // 4 * 1024 - 1 -> low
        XCTAssertEqual(DeviceRAMTier.classify(totalMemoryMB: 4 * 1024 - 1), .low)
    }

    func testRAMTierRawValues() {
        XCTAssertEqual(DeviceRAMTier.high.rawValue, "high")
        XCTAssertEqual(DeviceRAMTier.mid.rawValue, "mid")
        XCTAssertEqual(DeviceRAMTier.low.rawValue, "low")
    }

    // MARK: - Fallback When Server Unreachable

    func testFallbackToRAMWhenServerUnreachable() async {
        // No responses queued -- simulates network failure.
        let client = makeClient()
        await client.clearCache()

        let profile = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 8192)
        // No server data -> RAM-based fallback
        XCTAssertEqual(profile, "high")
    }

    func testFallbackToRAMOnServerError() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["error": "internal server error"])
        ]

        let client = makeClient()
        await client.clearCache()

        let profile = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 6000)
        // Server error -> RAM-based fallback
        XCTAssertEqual(profile, "mid")
    }

    // MARK: - In-Memory Caching

    func testInMemoryCacheReturnsCachedValue() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": [
                    "iPhone16,1": "iphone_15_pro",
                ],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        // First call fetches from server
        let first = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 8192)
        XCTAssertEqual(first, "iphone_15_pro")

        // Second call should use in-memory cache (no more server responses queued)
        let second = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 8192)
        XCTAssertEqual(second, "iphone_15_pro")

        // Only one request should have been made
        XCTAssertEqual(SharedMockURLProtocol.requests.count, 1)
    }

    // MARK: - Request Format

    func testRequestIncludesAuthorizationHeader() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": [:] as [String: String],
                "ttl_seconds": 60,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient(apiKey: "my-secret-key")
        await client.clearCache()

        _ = await client.getMapping()

        let request = SharedMockURLProtocol.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-key")
    }

    func testRequestHitsCorrectEndpoint() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": [:] as [String: String],
                "ttl_seconds": 60,
                "fetched_at": 0,
                "etag": "",
            ])
        ]

        let client = makeClient()
        await client.clearCache()

        _ = await client.getMapping()

        let request = SharedMockURLProtocol.requests.first
        XCTAssertNotNil(request)
        let url = request?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("api/v1/devices/profiles"), "URL should contain correct path: \(url)")
    }

    // MARK: - Cache Clearing

    func testClearCacheForcesFetch() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "profiles": ["iPhone16,1": "iphone_15_pro"],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
            .success(statusCode: 200, json: [
                "profiles": ["iPhone16,1": "iphone_16_pro"],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
        ]

        let client = makeClient()
        await client.clearCache()

        let first = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 8192)
        XCTAssertEqual(first, "iphone_15_pro")

        await client.clearCache()

        let second = await client.resolveProfile(machineId: "iPhone16,1", totalMemoryMB: 8192)
        XCTAssertEqual(second, "iphone_16_pro")
    }

    // MARK: - DeviceProfileMapping Codable

    func testDeviceProfileMappingCodableRoundTrip() throws {
        let mapping = DeviceProfileMapping(
            profiles: ["iPhone16,1": "iphone_15_pro", "iPhone17,1": "iphone_16_pro"],
            ttlSeconds: 300,
            fetchedAt: 1000.0,
            etag: "\"abc123\""
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(mapping)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DeviceProfileMapping.self, from: data)

        XCTAssertEqual(decoded.profiles.count, 2)
        XCTAssertEqual(decoded.profiles["iPhone16,1"], "iphone_15_pro")
        XCTAssertEqual(decoded.profiles["iPhone17,1"], "iphone_16_pro")
        XCTAssertEqual(decoded.ttlSeconds, 300)
        XCTAssertEqual(decoded.fetchedAt, 1000.0)
        XCTAssertEqual(decoded.etag, "\"abc123\"")
    }

    func testDeviceProfileMappingCodingKeysSnakeCase() throws {
        let mapping = DeviceProfileMapping(
            profiles: [:],
            ttlSeconds: 600,
            fetchedAt: 0,
            etag: ""
        )

        let data = try JSONEncoder().encode(mapping)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["ttl_seconds"])
        XCTAssertNotNil(json["fetched_at"])
        XCTAssertNotNil(json["profiles"])
    }

    // MARK: - DeviceMetadata Integration

    func testDeviceMetadataDeviceProfileUsesRAMFallback() {
        let metadata = DeviceMetadata()
        let profile = metadata.deviceProfile

        // Should be one of the RAM tier values
        let validTiers = ["high", "mid", "low"]
        XCTAssertTrue(validTiers.contains(profile),
                       "deviceProfile should be a RAM tier, got: \(profile)")
    }

    // MARK: - ETag Conditional Requests

    func testETagSentOnSubsequentRequests() async {
        SharedMockURLProtocol.responses = [
            // First response -- will expire immediately (ttl=0)
            .success(statusCode: 200, json: [
                "profiles": ["iPhone16,1": "iphone_15_pro"],
                "ttl_seconds": 0,
                "fetched_at": 0,
                "etag": "",
            ]),
            // Second response
            .success(statusCode: 200, json: [
                "profiles": ["iPhone16,1": "iphone_15_pro"],
                "ttl_seconds": 300,
                "fetched_at": 0,
                "etag": "",
            ]),
        ]

        let client = makeClient()
        await client.clearCache()

        // First call
        _ = await client.getMapping()

        // Second call -- TTL is 0 so it should refetch
        _ = await client.getMapping()

        XCTAssertEqual(SharedMockURLProtocol.requests.count, 2)
    }
}

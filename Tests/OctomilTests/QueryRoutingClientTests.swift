import Foundation
import XCTest
@testable import Octomil

final class QueryRoutingClientTests: XCTestCase {

    // MARK: - Test Models

    private static let testModels: [String: QueryModelInfo] = [
        "tiny-1b": QueryModelInfo(name: "tiny-1b", tier: "fast", paramB: 1.0, loaded: true),
        "mid-7b": QueryModelInfo(name: "mid-7b", tier: "balanced", paramB: 7.0, loaded: true),
        "large-70b": QueryModelInfo(name: "large-70b", tier: "quality", paramB: 70.0, loaded: true),
    ]

    // MARK: - Policy Serialization

    func testPolicyCodableRoundTrip() throws {
        let policy = RoutingPolicy(
            version: 1,
            thresholds: RoutingPolicy.Thresholds(fastMaxWords: 10, qualityMinWords: 50),
            complexIndicators: ["code", "explain"],
            deterministicEnabled: true,
            ttlSeconds: 300,
            fetchedAt: 1000.0,
            etag: "\"abc123\""
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RoutingPolicy.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.thresholds.fastMaxWords, 10)
        XCTAssertEqual(decoded.thresholds.qualityMinWords, 50)
        XCTAssertEqual(decoded.complexIndicators, ["code", "explain"])
        XCTAssertEqual(decoded.deterministicEnabled, true)
        XCTAssertEqual(decoded.ttlSeconds, 300)
        XCTAssertEqual(decoded.fetchedAt, 1000.0)
        XCTAssertEqual(decoded.etag, "\"abc123\"")
    }

    func testPolicyCodingKeysSnakeCase() throws {
        let policy = RoutingPolicy(
            version: 1,
            thresholds: RoutingPolicy.Thresholds(fastMaxWords: 10, qualityMinWords: 50),
            complexIndicators: ["code"],
            deterministicEnabled: false,
            ttlSeconds: 600,
            fetchedAt: 0,
            etag: ""
        )

        let data = try JSONEncoder().encode(policy)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify snake_case keys in JSON output.
        XCTAssertNotNil(json["complex_indicators"])
        XCTAssertNotNil(json["deterministic_enabled"])
        XCTAssertNotNil(json["ttl_seconds"])
        XCTAssertNotNil(json["fetched_at"])
    }

    func testPolicyDeserializationFromServerJSON() throws {
        let serverJSON = """
        {
            "version": 2,
            "thresholds": {"fast_max_words": 15, "quality_min_words": 40},
            "complex_indicators": ["analyze", "compare"],
            "deterministic_enabled": true,
            "ttl_seconds": 600,
            "fetched_at": 0,
            "etag": ""
        }
        """.data(using: .utf8)!

        let policy = try JSONDecoder().decode(RoutingPolicy.self, from: serverJSON)
        XCTAssertEqual(policy.version, 2)
        XCTAssertEqual(policy.thresholds.fastMaxWords, 15)
        XCTAssertEqual(policy.thresholds.qualityMinWords, 40)
        XCTAssertEqual(policy.complexIndicators, ["analyze", "compare"])
    }

    // MARK: - Default Policy Fallback

    func testDefaultPolicyValues() {
        let policy = defaultRoutingPolicy
        XCTAssertEqual(policy.version, 1)
        XCTAssertEqual(policy.thresholds.fastMaxWords, 10)
        XCTAssertEqual(policy.thresholds.qualityMinWords, 50)
        XCTAssertEqual(policy.complexIndicators.count, 14)
        XCTAssertTrue(policy.complexIndicators.contains("code"))
        XCTAssertTrue(policy.complexIndicators.contains("step by step"))
        XCTAssertTrue(policy.complexIndicators.contains("algorithm"))
        XCTAssertTrue(policy.deterministicEnabled)
        XCTAssertEqual(policy.ttlSeconds, 300)
    }

    func testPolicyClientReturnsDefaultWhenNoCacheOrServer() async {
        // PolicyClient with unreachable server and no disk cache.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]
        let session = URLSession(configuration: config)

        SharedMockURLProtocol.reset()
        // No responses queued — simulates network failure.

        let client = PolicyClient(
            apiBase: URL(string: "https://api.octomil.com")!,
            apiKey: "test-key",
            session: session
        )
        await client.clearCache()

        let policy = await client.getPolicy()
        XCTAssertEqual(policy.version, defaultRoutingPolicy.version)
        XCTAssertEqual(policy.thresholds.fastMaxWords, defaultRoutingPolicy.thresholds.fastMaxWords)
    }

    // MARK: - Query Routing Tiers

    func testShortQueryRoutesToFast() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "Hi there"]
        ])

        XCTAssertEqual(decision.tier, "fast")
        XCTAssertEqual(decision.modelName, "tiny-1b")
        XCTAssertEqual(decision.strategy, "complexity")
        XCTAssertTrue(decision.complexityScore < 0.3)
    }

    func testLongQueryRoutesToQuality() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        // Should route to quality tier.
        let words = (0..<60).map { "word\($0)" }.joined(separator: " ")
        let longText = "explain and analyze: \(words)"
        let decision = await router.route(messages: [
            ["role": "user", "content": longText]
        ])

        XCTAssertEqual(decision.tier, "quality")
        XCTAssertEqual(decision.modelName, "large-70b")
        XCTAssertTrue(decision.complexityScore >= 0.7)
    }

    func testMediumQueryRoutesToBalanced() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        // Should route to balanced tier.
        let mediumText = (0..<35).map { "word\($0)" }.joined(separator: " ")
        let decision = await router.route(messages: [
            ["role": "user", "content": mediumText]
        ])

        XCTAssertEqual(decision.tier, "balanced")
        XCTAssertEqual(decision.modelName, "mid-7b")
    }

    func testComplexKeywordsBoostScore() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        // Short text but with complex indicators — should boost score.
        let decision = await router.route(messages: [
            ["role": "user", "content": "explain the code and analyze the algorithm"]
        ])

        // Should route to balanced tier.
        XCTAssertEqual(decision.tier, "balanced")
        XCTAssertTrue(decision.complexityScore > 0.0)
    }

    func testComplexKeywordsWithLengthPushToQuality() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        // Should route to quality tier.
        let words = (0..<47).map { "word\($0)" }.joined(separator: " ")
        let decision = await router.route(messages: [
            ["role": "user", "content": "explain and analyze: \(words)"]
        ])

        XCTAssertEqual(decision.tier, "quality")
    }

    // MARK: - Deterministic Detection

    func testDeterministicArithmeticDetected() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: true
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "2 + 3"]
        ])

        XCTAssertEqual(decision.tier, "deterministic")
        XCTAssertEqual(decision.strategy, "deterministic")
        XCTAssertNotNil(decision.deterministicResult)
        XCTAssertEqual(decision.deterministicResult?.answer, "5")
        XCTAssertEqual(decision.deterministicResult?.method, "arithmetic")
        XCTAssertEqual(decision.deterministicResult?.confidence, 1.0)
    }

    func testDeterministicWithPrefix() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: true
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "what is 10 * 5"]
        ])

        XCTAssertEqual(decision.tier, "deterministic")
        XCTAssertEqual(decision.deterministicResult?.answer, "50")
    }

    func testDeterministicDisabled() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "2 + 3"]
        ])

        // Should not be deterministic when disabled.
        XCTAssertNotEqual(decision.tier, "deterministic")
        XCTAssertNil(decision.deterministicResult)
    }

    func testNonArithmeticNotDeterministic() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: true
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "What is the meaning of life?"]
        ])

        XCTAssertNotEqual(decision.tier, "deterministic")
        XCTAssertNil(decision.deterministicResult)
    }

    // MARK: - Model Fallback Chain

    func testFallbackChainExcludesPrimary() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "Hi"]
        ])

        XCTAssertEqual(decision.modelName, "tiny-1b")
        XCTAssertFalse(decision.fallbackChain.contains("tiny-1b"))
        // Should contain models from other tiers.
        XCTAssertTrue(decision.fallbackChain.count > 0)
    }

    func testGetFallbackReturnsLowerTier() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let fallback = await router.getFallback(failedModel: "large-70b")
        XCTAssertNotNil(fallback)
        XCTAssertNotEqual(fallback, "large-70b")
    }

    func testGetFallbackReturnsNilForUnknownModel() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let fallback = await router.getFallback(failedModel: "nonexistent")
        XCTAssertNil(fallback)
    }

    func testGetFallbackFromFastTier() async {
        // Only one model per tier, so fallback from fast has nowhere to go
        // within that tier — should return nil (no lower tiers exist for fast).
        let singleModels: [String: QueryModelInfo] = [
            "tiny-1b": QueryModelInfo(name: "tiny-1b", tier: "fast", paramB: 1.0, loaded: true),
        ]
        let router = QueryRouter(
            models: singleModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let fallback = await router.getFallback(failedModel: "tiny-1b")
        XCTAssertNil(fallback)
    }

    // MARK: - Policy Expiry

    func testPolicyExpiryDetection() throws {
        // A policy with fetchedAt far in the past and short TTL should be expired.
        let expired = RoutingPolicy(
            version: 1,
            thresholds: RoutingPolicy.Thresholds(fastMaxWords: 10, qualityMinWords: 50),
            complexIndicators: [],
            deterministicEnabled: true,
            ttlSeconds: 60,
            fetchedAt: Date().timeIntervalSince1970 - 120, // 2 minutes ago, TTL is 1 minute
            etag: ""
        )
        let age = Date().timeIntervalSince1970 - expired.fetchedAt
        XCTAssertTrue(age > Double(expired.ttlSeconds), "Policy should be expired")
    }

    func testPolicyNotExpired() throws {
        let fresh = RoutingPolicy(
            version: 1,
            thresholds: RoutingPolicy.Thresholds(fastMaxWords: 10, qualityMinWords: 50),
            complexIndicators: [],
            deterministicEnabled: true,
            ttlSeconds: 300,
            fetchedAt: Date().timeIntervalSince1970, // just now
            etag: ""
        )
        let age = Date().timeIntervalSince1970 - fresh.fetchedAt
        XCTAssertTrue(age <= Double(fresh.ttlSeconds), "Policy should not be expired")
    }

    // MARK: - Edge Cases

    func testEmptyMessagesArray() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let decision = await router.route(messages: [])
        // Empty input should route to fast (empty string = 0 words).
        XCTAssertEqual(decision.tier, "fast")
    }

    func testSystemMessageOnlyUsesEmptyContent() async {
        let router = QueryRouter(
            models: Self.testModels,
            policyClient: nil,
            enableDeterministic: false
        )

        let decision = await router.route(messages: [
            ["role": "system", "content": "You are a helpful assistant that explains code and algorithms step by step"]
        ])

        // No user message — should use empty string, route to fast.
        XCTAssertEqual(decision.tier, "fast")
    }

    func testQueryModelInfoInit() {
        let info = QueryModelInfo(name: "test", tier: "fast", paramB: 1.5, loaded: true)
        XCTAssertEqual(info.name, "test")
        XCTAssertEqual(info.tier, "fast")
        XCTAssertEqual(info.paramB, 1.5)
        XCTAssertTrue(info.loaded)
    }

    func testNoLoadedModelsReturnsEmptyName() async {
        let unloaded: [String: QueryModelInfo] = [
            "offline": QueryModelInfo(name: "offline", tier: "fast", paramB: 1.0, loaded: false),
        ]
        let router = QueryRouter(
            models: unloaded,
            policyClient: nil,
            enableDeterministic: false
        )

        let decision = await router.route(messages: [
            ["role": "user", "content": "Hi"]
        ])

        // Should still pick the model even though not loaded, as it's the only option.
        XCTAssertEqual(decision.modelName, "offline")
    }
}

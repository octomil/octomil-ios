import Foundation
import XCTest
@testable import OctomilMLX

final class MLXInferenceMetricsTests: XCTestCase {

    // MARK: - InferenceMetrics Codable

    func testInferenceMetricsCodableRoundTrip() throws {
        let metrics = InferenceMetrics(
            ttfcMs: 42.5,
            promptTokens: 128,
            totalTokens: 256,
            tokensPerSecond: 65.3,
            totalDurationMs: 3923.1,
            cacheHit: true,
            attentionBackend: "metal"
        )

        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(InferenceMetrics.self, from: data)

        XCTAssertEqual(decoded.ttfcMs, 42.5)
        XCTAssertEqual(decoded.promptTokens, 128)
        XCTAssertEqual(decoded.totalTokens, 256)
        XCTAssertEqual(decoded.tokensPerSecond, 65.3)
        XCTAssertEqual(decoded.totalDurationMs, 3923.1)
        XCTAssertTrue(decoded.cacheHit)
        XCTAssertEqual(decoded.attentionBackend, "metal")
    }

    func testInferenceMetricsSnakeCaseKeys() throws {
        let metrics = InferenceMetrics(
            ttfcMs: 10.0,
            promptTokens: 32,
            totalTokens: 64,
            tokensPerSecond: 100.0,
            totalDurationMs: 640.0,
            cacheHit: false,
            attentionBackend: nil
        )

        let data = try JSONEncoder().encode(metrics)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["ttfc_ms"])
        XCTAssertNotNil(json["prompt_tokens"])
        XCTAssertNotNil(json["total_tokens"])
        XCTAssertNotNil(json["tokens_per_second"])
        XCTAssertNotNil(json["total_duration_ms"])
        XCTAssertNotNil(json["cache_hit"])
        // camelCase keys should NOT be present
        XCTAssertNil(json["ttfcMs"])
        XCTAssertNil(json["promptTokens"])
    }

    func testInferenceMetricsNilAttentionBackend() throws {
        let metrics = InferenceMetrics(
            ttfcMs: 5.0,
            promptTokens: 16,
            totalTokens: 32,
            tokensPerSecond: 200.0,
            totalDurationMs: 160.0,
            cacheHit: false,
            attentionBackend: nil
        )

        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(InferenceMetrics.self, from: data)
        XCTAssertNil(decoded.attentionBackend)
    }

    // MARK: - CacheStats Codable

    func testCacheStatsCodableRoundTrip() throws {
        let stats = CacheStats(
            hits: 42,
            misses: 8,
            hitRate: 0.84,
            entries: 3,
            memoryMb: 256.5
        )

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(CacheStats.self, from: data)

        XCTAssertEqual(decoded.hits, 42)
        XCTAssertEqual(decoded.misses, 8)
        XCTAssertEqual(decoded.hitRate, 0.84, accuracy: 0.001)
        XCTAssertEqual(decoded.entries, 3)
        XCTAssertEqual(decoded.memoryMb, 256.5, accuracy: 0.001)
    }

    func testCacheStatsSnakeCaseKeys() throws {
        let stats = CacheStats(hits: 1, misses: 0, hitRate: 1.0, entries: 1, memoryMb: 64.0)

        let data = try JSONEncoder().encode(stats)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["hit_rate"])
        XCTAssertNotNil(json["memory_mb"])
        XCTAssertNil(json["hitRate"])
        XCTAssertNil(json["memoryMb"])
    }

    // MARK: - GenerationChunk

    func testGenerationChunkConstruction() {
        let chunk = GenerationChunk(
            text: "Hello",
            tokenCount: 1,
            tokensPerSecond: 55.0,
            finishReason: nil
        )

        XCTAssertEqual(chunk.text, "Hello")
        XCTAssertEqual(chunk.tokenCount, 1)
        XCTAssertEqual(chunk.tokensPerSecond, 55.0)
        XCTAssertNil(chunk.finishReason)
    }

    func testGenerationChunkWithFinishReason() {
        let chunk = GenerationChunk(
            text: "",
            tokenCount: 0,
            tokensPerSecond: 0.0,
            finishReason: "stop"
        )

        XCTAssertEqual(chunk.finishReason, "stop")
    }
}

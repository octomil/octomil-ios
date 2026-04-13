import Foundation
import XCTest
@testable import Octomil

final class RuntimePlannerStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: RuntimePlannerStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-planner-test-\(UUID().uuidString)", isDirectory: true)
        store = RuntimePlannerStore(cacheDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Cache Key

    func testMakeCacheKeyDeterministic() {
        let key1 = RuntimePlannerStore.makeCacheKey([
            "model": "llama-8b",
            "capability": "text",
            "policy": "local_first",
        ])
        let key2 = RuntimePlannerStore.makeCacheKey([
            "policy": "local_first",
            "model": "llama-8b",
            "capability": "text",
        ])

        XCTAssertEqual(key1, key2, "Cache key should be deterministic regardless of dict ordering")
        XCTAssertEqual(key1.count, 32, "Cache key should be 32 hex chars")
    }

    func testMakeCacheKeyDifferentForDifferentInputs() {
        let key1 = RuntimePlannerStore.makeCacheKey(["model": "llama-8b"])
        let key2 = RuntimePlannerStore.makeCacheKey(["model": "gemma-2b"])

        XCTAssertNotEqual(key1, key2)
    }

    func testMakeCacheKeyHandlesNilValues() {
        let key1 = RuntimePlannerStore.makeCacheKey(["model": nil])
        let key2 = RuntimePlannerStore.makeCacheKey(["model": ""])

        // nil and empty string both produce empty value in key generation
        XCTAssertEqual(key1, key2)
    }

    // MARK: - Plan Cache

    func testPutAndGetPlan() {
        let plan = makeSamplePlan()
        let key = "test-plan-key"

        store.putPlan(
            cacheKey: key,
            model: "llama-8b",
            capability: "text",
            policy: "local_first",
            plan: plan,
            source: "server_plan"
        )

        let retrieved = store.getPlan(cacheKey: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.model, "llama-8b")
        XCTAssertEqual(retrieved?.capability, "text")
        XCTAssertEqual(retrieved?.candidates.count, 1)
    }

    func testGetPlanReturnsNilForMissingKey() {
        let result = store.getPlan(cacheKey: "nonexistent")
        XCTAssertNil(result)
    }

    func testGetPlanReturnsNilForExpiredEntry() {
        // Create a plan with TTL of 0 (already expired)
        let plan = RuntimePlanResponse(
            model: "test",
            capability: "text",
            policy: "local_first",
            candidates: [],
            planTtlSeconds: 0 // Immediately expires
        )

        let key = "expired-plan"
        store.putPlan(
            cacheKey: key,
            model: "test",
            capability: "text",
            policy: "local_first",
            plan: plan,
            source: "test"
        )

        // The entry was created with expiresAt = now + 0, so it should be expired
        // (or at the boundary). Wait a tiny bit to ensure expiry.
        Thread.sleep(forTimeInterval: 0.01)

        let result = store.getPlan(cacheKey: key)
        XCTAssertNil(result, "Expired plan should return nil")
    }

    func testPlanOverwrite() {
        let key = "overwrite-test"

        let plan1 = RuntimePlanResponse(
            model: "model-1",
            capability: "text",
            policy: "local_first",
            candidates: []
        )
        let plan2 = RuntimePlanResponse(
            model: "model-2",
            capability: "text",
            policy: "cloud_first",
            candidates: []
        )

        store.putPlan(cacheKey: key, model: "model-1", capability: "text", policy: "local_first", plan: plan1, source: "test")
        store.putPlan(cacheKey: key, model: "model-2", capability: "text", policy: "cloud_first", plan: plan2, source: "test")

        let retrieved = store.getPlan(cacheKey: key)
        XCTAssertEqual(retrieved?.model, "model-2")
    }

    // MARK: - Benchmark Cache

    func testPutAndGetBenchmark() {
        let key = "bm-test-key"

        store.putBenchmark(
            cacheKey: key,
            model: "llama-8b",
            capability: "text",
            engine: "mlx",
            policy: "local_first",
            tokensPerSecond: 85.0,
            ttftMs: 120.0,
            memoryMb: 512.0
        )

        let retrieved = store.getBenchmark(cacheKey: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.model, "llama-8b")
        XCTAssertEqual(retrieved?.engine, "mlx-lm")
        XCTAssertEqual(retrieved?.tokensPerSecond, 85.0)
        XCTAssertEqual(retrieved?.ttftMs, 120.0)
        XCTAssertEqual(retrieved?.memoryMb, 512.0)
    }

    func testGetBenchmarkReturnsNilForMissingKey() {
        let result = store.getBenchmark(cacheKey: "nonexistent")
        XCTAssertNil(result)
    }

    func testGetBenchmarkReturnsNilForExpiredEntry() {
        let key = "expired-bm"

        store.putBenchmark(
            cacheKey: key,
            model: "test",
            capability: "text",
            engine: "coreml",
            ttlSeconds: 0
        )

        Thread.sleep(forTimeInterval: 0.01)

        let result = store.getBenchmark(cacheKey: key)
        XCTAssertNil(result, "Expired benchmark should return nil")
    }

    // MARK: - Clear

    func testClearAllRemovesBothCaches() {
        let planKey = "plan-key"
        let bmKey = "bm-key"

        store.putPlan(
            cacheKey: planKey,
            model: "test",
            capability: "text",
            policy: "local_first",
            plan: makeSamplePlan(),
            source: "test"
        )
        store.putBenchmark(
            cacheKey: bmKey,
            model: "test",
            capability: "text",
            engine: "mlx"
        )

        // Verify both exist
        XCTAssertNotNil(store.getPlan(cacheKey: planKey))
        XCTAssertNotNil(store.getBenchmark(cacheKey: bmKey))

        store.clearAll()

        XCTAssertNil(store.getPlan(cacheKey: planKey))
        XCTAssertNil(store.getBenchmark(cacheKey: bmKey))
    }

    // MARK: - Persistence

    func testPlanPersistsAcrossInstances() {
        let key = "persist-test"
        let plan = makeSamplePlan()

        store.putPlan(
            cacheKey: key,
            model: "llama-8b",
            capability: "text",
            policy: "local_first",
            plan: plan,
            source: "server_plan"
        )

        // Create a new store instance pointing at the same directory
        let store2 = RuntimePlannerStore(cacheDirectory: tempDir)
        let retrieved = store2.getPlan(cacheKey: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.model, "llama-8b")
    }

    func testBenchmarkPersistsAcrossInstances() {
        let key = "bm-persist"

        store.putBenchmark(
            cacheKey: key,
            model: "test",
            capability: "text",
            engine: "mlx",
            tokensPerSecond: 90.0
        )

        let store2 = RuntimePlannerStore(cacheDirectory: tempDir)
        let retrieved = store2.getBenchmark(cacheKey: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.tokensPerSecond, 90.0)
    }

    // MARK: - Helpers

    private func makeSamplePlan() -> RuntimePlanResponse {
        RuntimePlanResponse(
            model: "llama-8b",
            capability: "text",
            policy: "local_first",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 1,
                    confidence: 0.9,
                    reason: "Best for this device",
                    engine: "mlx"
                ),
            ],
            planTtlSeconds: 86400
        )
    }
}

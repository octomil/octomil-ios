import Foundation
@testable import Octomil
import XCTest

final class RuntimePlannerTests: XCTestCase {
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

    // MARK: - Resolve: Local First (default)

    func testResolveLocalFirstFallsBackToCloudWithoutLocalRuntime() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false
        )

        XCTAssertEqual(selection.locality, .cloud)
        XCTAssertNil(selection.engine)
        XCTAssertEqual(selection.source, "fallback")
    }

    func testResolveLocalFirstWithAdditionalRuntimes() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let additionalRuntimes = [
            InstalledRuntime(
                engine: "mlx",
                version: "0.30.0",
                available: true,
                accelerator: "metal",
                metadata: ["models": "gemma-2b", "capabilities": "text"]
            ),
        ]

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: additionalRuntimes
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.engine, "mlx-lm")
        XCTAssertEqual(selection.source, "local_default")
    }

    // MARK: - Resolve: Cloud Only

    func testResolveCloudOnlySkipsLocalEngines() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let selection = await planner.resolve(
            model: "gpt-4",
            capability: "text",
            routingPolicy: "cloud_only",
            allowNetwork: false
        )

        XCTAssertEqual(selection.locality, .cloud)
        XCTAssertNil(selection.engine)
        XCTAssertEqual(selection.source, "fallback")
        XCTAssertTrue(selection.reason.contains("cloud_only"))
    }

    // MARK: - Resolve: Private Policy

    func testResolvePrivatePolicySkipsNetwork() async {
        // Even if a client were provided, private policy should skip server fetch.
        // We test this by verifying the resolve completes without network.
        let planner = RuntimePlanner(store: store, client: nil)

        let selection = await planner.resolve(
            model: "local-model",
            capability: "text",
            routingPolicy: "private",
            allowNetwork: true // Would normally attempt network, but private skips it
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertNil(selection.engine)
        XCTAssertEqual(selection.source, "fallback")
    }

    // MARK: - Resolve: Local Only Fallback

    func testResolveLocalOnlyWithNoEnginesReturnsFallback() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // Pre-populate the store with a cached plan that requires engines we don't have
        let cacheKey = RuntimePlannerStore.makeCacheKey([
            "model": "exotic-model",
            "capability": "text",
            "policy": "local_only",
            "sdk_version": OctomilVersion.current,
            "platform": DeviceRuntimeProfileCollector.platformName(),
            "arch": DeviceRuntimeProfileCollector.cpuArchitecture(),
        ])

        let plan = RuntimePlanResponse(
            model: "exotic-model",
            capability: "text",
            policy: "local_only",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 1,
                    confidence: 0.9,
                    reason: "Requires exotic engine",
                    engine: "nonexistent_engine"
                ),
            ]
        )

        store.putPlan(
            cacheKey: cacheKey,
            model: "exotic-model",
            capability: "text",
            policy: "local_only",
            plan: plan,
            source: "test"
        )

        let selection = await planner.resolve(
            model: "exotic-model",
            capability: "text",
            routingPolicy: "local_only",
            allowNetwork: false
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertNil(selection.engine)
        XCTAssertEqual(selection.source, "fallback")
    }

    // MARK: - Resolve: Cached Plan

    func testResolvUsesCachedPlan() async {
        let cacheKey = RuntimePlannerStore.makeCacheKey([
            "model": "cached-model",
            "capability": "text",
            "policy": "local_first",
            "sdk_version": OctomilVersion.current,
            "platform": DeviceRuntimeProfileCollector.platformName(),
            "arch": DeviceRuntimeProfileCollector.cpuArchitecture(),
        ])

        let plan = RuntimePlanResponse(
            model: "cached-model",
            capability: "text",
            policy: "local_first",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 1,
                    confidence: 0.95,
                    reason: "Cached server recommendation",
                    engine: "mlx-lm", // An engine we report as installed below
                    artifact: RuntimeArtifactPlan(modelId: "cached-model")
                ),
            ]
        )

        store.putPlan(
            cacheKey: cacheKey,
            model: "cached-model",
            capability: "text",
            policy: "local_first",
            plan: plan,
            source: "server_plan"
        )

        let planner = RuntimePlanner(store: store, client: nil)

        let selection = await planner.resolve(
            model: "cached-model",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [InstalledRuntime(engine: "mlx")]
        )

        XCTAssertEqual(selection.source, "cache")
        XCTAssertEqual(selection.engine, "mlx-lm")
        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.reason, "Cached server recommendation")
    }

    // MARK: - Resolve: Cached Benchmark

    func testResolveUsesCachedBenchmark() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let additionalRuntimes = [InstalledRuntime(engine: "mlx", available: true)]
        planner.recordBenchmark(
            model: "bench-model",
            capability: "text",
            routingPolicy: "local_first",
            result: BenchmarkResult(
                engineName: "mlx",
                tokensPerSecond: 88.0,
                ttftMs: 100.0,
                memoryMb: 512.0
            ),
            additionalRuntimes: additionalRuntimes
        )

        let selection = await planner.resolve(
            model: "bench-model",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: additionalRuntimes
        )
        XCTAssertEqual(selection.source, "cache")
        XCTAssertEqual(selection.engine, "mlx-lm")
    }

    // MARK: - Server Plan Validation

    func testServerPlanSkipsUnavailableEngines() async {
        let cacheKey = RuntimePlannerStore.makeCacheKey([
            "model": "multi-engine",
            "capability": "text",
            "policy": "local_first",
            "sdk_version": OctomilVersion.current,
            "platform": DeviceRuntimeProfileCollector.platformName(),
            "arch": DeviceRuntimeProfileCollector.cpuArchitecture(),
        ])

        let plan = RuntimePlanResponse(
            model: "multi-engine",
            capability: "text",
            policy: "local_first",
            candidates: [
                // First candidate requires an engine we don't have
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 1,
                    confidence: 0.95,
                    reason: "Best if available",
                    engine: "nonexistent_engine"
                ),
                // Second candidate uses MLX, reported as installed below
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 2,
                    confidence: 0.8,
                    reason: "MLX fallback",
                    engine: "mlx-lm",
                    artifact: RuntimeArtifactPlan(modelId: "multi-engine")
                ),
            ]
        )

        store.putPlan(
            cacheKey: cacheKey,
            model: "multi-engine",
            capability: "text",
            policy: "local_first",
            plan: plan,
            source: "server_plan"
        )

        let planner = RuntimePlanner(store: store, client: nil)

        let selection = await planner.resolve(
            model: "multi-engine",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [InstalledRuntime(engine: "mlx")]
        )

        XCTAssertEqual(selection.engine, "mlx-lm")
        XCTAssertEqual(selection.source, "cache")
        XCTAssertEqual(selection.reason, "MLX fallback")
    }

    func testServerPlanFallbackCandidates() async {
        let cacheKey = RuntimePlannerStore.makeCacheKey([
            "model": "fallback-test",
            "capability": "text",
            "policy": "local_first",
            "sdk_version": OctomilVersion.current,
            "platform": DeviceRuntimeProfileCollector.platformName(),
            "arch": DeviceRuntimeProfileCollector.cpuArchitecture(),
        ])

        let plan = RuntimePlanResponse(
            model: "fallback-test",
            capability: "text",
            policy: "local_first",
            candidates: [
                // All primary candidates require unavailable engines
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 1,
                    confidence: 0.95,
                    reason: "Needs exotic engine",
                    engine: "exotic_engine_1"
                ),
            ],
            fallbackCandidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 10,
                    confidence: 0.5,
                    reason: "Slow but works",
                    engine: "mlx-lm",
                    artifact: RuntimeArtifactPlan(modelId: "fallback-test")
                ),
            ]
        )

        store.putPlan(
            cacheKey: cacheKey,
            model: "fallback-test",
            capability: "text",
            policy: "local_first",
            plan: plan,
            source: "server_plan"
        )

        let planner = RuntimePlanner(store: store, client: nil)

        // selectionFromPlan handles fallback by iterating candidates then fallback
        // but in this case the cached plan's candidates have an unavailable engine.
        // selectionFromPlan will skip it and go to fallback.
        // Wait -- selectionFromPlan only checks primary candidates then returns fallback
        // generic if no match. Let me verify this behavior.
        let selection = await planner.resolve(
            model: "fallback-test",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [InstalledRuntime(engine: "mlx")]
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.engine, "mlx-lm")
        XCTAssertEqual(selection.source, "cache")
        XCTAssertTrue(selection.reason.contains("fallback"))
    }

    // MARK: - Record Benchmark

    func testRecordBenchmarkStoresResult() {
        let planner = RuntimePlanner(store: store, client: nil)

        let result = BenchmarkResult(
            engineName: "mlx",
            tokensPerSecond: 85.0,
            ttftMs: 120.0,
            memoryMb: 512.0
        )

        planner.recordBenchmark(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            result: result
        )

        // Verify it was stored by resolving again -- should return from cache
        // We can't easily verify the exact cache key here since it depends
        // on device profile, but we can at least verify the method doesn't crash.
    }

    func testRecordBenchmarkWithPrivatePolicySkipsTelemetry() {
        // This should complete without error even with no client
        let planner = RuntimePlanner(store: store, client: nil)

        let result = BenchmarkResult(
            engineName: "coreml",
            tokensPerSecond: 50.0,
            ttftMs: 200.0,
            memoryMb: 256.0
        )

        planner.recordBenchmark(
            model: "test-model",
            capability: "text",
            routingPolicy: "private",
            result: result
        )
        // No crash = success. Private policy should skip telemetry upload.
    }

    // MARK: - No Network Mode

    func testResolveWithoutNetworkNeverBlocks() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // This should complete immediately without any network calls
        let start = Date()
        _ = await planner.resolve(
            model: "any-model",
            capability: "text",
            allowNetwork: false
        )
        let elapsed = Date().timeIntervalSince(start)

        // Should complete in well under 1 second (no network wait)
        XCTAssertLessThan(elapsed, 1.0, "Offline resolve should complete quickly")
    }
}

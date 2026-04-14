import Foundation
import XCTest
@testable import Octomil

/// End-to-end smoke tests for runtime planner routing policy behavior.
///
/// These tests exercise the full ``RuntimePlanner`` resolution path — from
/// device profile collection through evidence matching, benchmark cache
/// lookup, and final ``RuntimeSelection`` — without mocking the planner
/// itself. Only the network client is omitted (nil) to keep tests hermetic.
///
/// Each test verifies a product-level routing invariant:
/// - Framework availability alone does NOT prove model capability
/// - Private policy must never produce cloud candidates
/// - Cloud-only policy must never attempt local resolution
/// - Benchmark cache is only used after a real benchmark write
final class RuntimePlannerE2ETests: XCTestCase {

    private var tempDir: URL!
    private var store: RuntimePlannerStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "octomil-e2e-test-\(UUID().uuidString)",
                isDirectory: true
            )
        store = RuntimePlannerStore(cacheDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Create a model-capable llama.cpp runtime with evidence for a specific model.
    private func llamaCppEvidence(
        model: String,
        capabilities: [String] = ["text"]
    ) -> InstalledRuntime {
        InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: model,
            capabilities: capabilities,
            version: "b4000",
            accelerator: "metal",
            artifactFormat: "gguf"
        )
    }

    /// Create a bare runtime with framework detection only — no model evidence.
    private func bareRuntime(engine: String) -> InstalledRuntime {
        InstalledRuntime(
            engine: engine,
            version: "1.0.0",
            available: true,
            accelerator: "metal"
        )
    }

    // MARK: - Test 1: private policy → local engine, no cloud

    /// When a local-capable runtime has model evidence and routing policy is
    /// `private`, the planner MUST select the local engine and MUST NOT produce
    /// a cloud candidate. Private policy guarantees no data leaves the device.
    func testPrivatePolicySelectsLocalEngineNeverCloud() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let evidence = llamaCppEvidence(model: "llama-8b")

        let selection = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "private",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        // Must be local
        XCTAssertEqual(
            selection.locality, .local,
            "Private policy with local evidence must resolve to local"
        )
        XCTAssertEqual(
            selection.engine, "llama.cpp",
            "Should select the llama.cpp engine that has model evidence"
        )

        // Must NOT be cloud
        XCTAssertNotEqual(
            selection.locality, .cloud,
            "Private policy must never produce a cloud selection"
        )

        // Source should be local_default (not fallback or cache)
        XCTAssertEqual(
            selection.source, "local_default",
            "Selection should come from local engine matching, not fallback"
        )
    }

    /// Private policy with no local evidence must still resolve to local
    /// (with nil engine), never cloud — even if that means no engine is available.
    func testPrivatePolicyNeverFallsBackToCloud() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let selection = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "private",
            allowNetwork: true // private skips network regardless
        )

        XCTAssertEqual(
            selection.locality, .local,
            "Private policy must stay local even when no engine is available"
        )
        XCTAssertNotEqual(
            selection.locality, .cloud,
            "Private policy must never produce a cloud selection"
        )
    }

    // MARK: - Test 2: local_first + local evidence → local primary

    /// When a model-capable runtime exists and routing policy is `local_first`,
    /// the planner should select the local engine as the primary choice.
    func testLocalFirstWithEvidenceSelectsLocal() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let evidence = llamaCppEvidence(model: "gemma-2b")

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(
            selection.locality, .local,
            "local_first with model evidence must resolve to local"
        )
        XCTAssertEqual(
            selection.engine, "llama.cpp",
            "Should select the engine with matching model evidence"
        )
        XCTAssertEqual(
            selection.source, "local_default",
            "Should be resolved via local engine matching"
        )
    }

    /// When multiple engines have evidence for the same model, the first
    /// reported engine should be selected (stable ordering).
    func testLocalFirstSelectsFirstMatchingEngine() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let llamaEvidence = llamaCppEvidence(model: "phi-3")
        let mlxEvidence = InstalledRuntime.modelCapable(
            engine: "mlx",
            model: "phi-3",
            capabilities: ["text"],
            version: "0.30.0",
            accelerator: "metal"
        )

        // llama.cpp is first in the array → should be selected
        let selection = await planner.resolve(
            model: "phi-3",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [llamaEvidence, mlxEvidence]
        )

        XCTAssertEqual(selection.locality, .local)
        // The first matching engine in additionalRuntimes ordering should win.
        // DeviceRuntimeProfileCollector appends additionalRuntimes after core
        // runtimes (which are empty), so llama.cpp comes first.
        XCTAssertEqual(selection.engine, "llama.cpp")
    }

    // MARK: - Test 3: local_first + no model artifact → cloud fallback

    /// Framework detection without model evidence is NOT sufficient for local
    /// resolution. The planner must fall back to cloud when no runtime has
    /// model-specific evidence.
    func testLocalFirstWithoutEvidenceFallsBackToCloud() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // Only framework detection — no model/capability metadata
        let bare = bareRuntime(engine: "mlx")

        let selection = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [bare]
        )

        XCTAssertEqual(
            selection.locality, .cloud,
            "Framework-only runtime without model evidence must fall back to cloud"
        )
        XCTAssertEqual(
            selection.source, "fallback",
            "Source should be fallback since no local engine matched"
        )
        XCTAssertTrue(
            selection.reason.contains("cloud") || selection.reason.contains("no local"),
            "Reason should indicate cloud fallback: \(selection.reason)"
        )
    }

    /// Even with multiple bare runtimes installed, none should match without
    /// model evidence.
    func testLocalFirstWithMultipleBareRuntimesFallsBackToCloud() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let runtimes = [
            bareRuntime(engine: "mlx"),
            bareRuntime(engine: "llama.cpp"),
            bareRuntime(engine: "coreml"),
        ]

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: runtimes
        )

        XCTAssertEqual(
            selection.locality, .cloud,
            "Multiple bare runtimes without evidence must still fall back to cloud"
        )
    }

    // MARK: - Test 4: cloud_only → cloud, even with local evidence

    /// Cloud-only policy must select cloud even when a fully-capable local
    /// runtime is available. The planner should skip all local engine work.
    func testCloudOnlySelectsCloudEvenWithLocalEvidence() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let evidence = llamaCppEvidence(model: "llama-8b")

        let selection = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "cloud_only",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(
            selection.locality, .cloud,
            "cloud_only must select cloud regardless of local evidence"
        )
        XCTAssertTrue(
            selection.reason.contains("cloud_only"),
            "Reason should reference cloud_only policy: \(selection.reason)"
        )
    }

    /// Cloud-only should also select cloud with multiple model-capable engines.
    func testCloudOnlyIgnoresMultipleCapableEngines() async {
        let planner = RuntimePlanner(store: store, client: nil)

        let runtimes = [
            llamaCppEvidence(model: "llama-8b"),
            InstalledRuntime.modelCapable(
                engine: "mlx",
                model: "llama-8b",
                capabilities: ["text"],
                accelerator: "metal"
            ),
        ]

        let selection = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "cloud_only",
            allowNetwork: false,
            additionalRuntimes: runtimes
        )

        XCTAssertEqual(selection.locality, .cloud)
        XCTAssertEqual(selection.source, "fallback")
    }

    /// Cloud-only should select cloud even when a benchmark cache exists for
    /// a local engine. The benchmark cache must be skipped entirely.
    func testCloudOnlyIgnoresBenchmarkCache() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let evidence = llamaCppEvidence(model: "bench-model")

        // Record a benchmark that would normally cause cache hit
        planner.recordBenchmark(
            model: "bench-model",
            capability: "text",
            routingPolicy: "cloud_only",
            result: BenchmarkResult(
                engineName: "llama.cpp",
                tokensPerSecond: 95.0,
                ttftMs: 80.0,
                memoryMb: 400.0
            ),
            additionalRuntimes: [evidence]
        )

        let selection = await planner.resolve(
            model: "bench-model",
            capability: "text",
            routingPolicy: "cloud_only",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(
            selection.locality, .cloud,
            "cloud_only must select cloud even when benchmark cache exists"
        )
    }

    // MARK: - Test 5: Benchmark cache lifecycle

    /// Resolution without a prior benchmark write must NOT use benchmark cache.
    /// After a real benchmark write via `recordBenchmark()`, subsequent
    /// resolution MUST use the cached benchmark data.
    func testBenchmarkCacheOnlyUsedAfterRealWrite() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // A bare runtime (no model evidence) — forces fallback path
        let bare = bareRuntime(engine: "llama.cpp")

        // Step 1: Resolve BEFORE any benchmark — should NOT find cache
        let selectionBefore = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [bare]
        )

        // Without evidence or benchmark cache, bare runtime → cloud fallback
        XCTAssertEqual(
            selectionBefore.locality, .cloud,
            "Before benchmark write, bare runtime must fall back to cloud"
        )
        XCTAssertNotEqual(
            selectionBefore.source, "cache",
            "Source must not be 'cache' before any benchmark is recorded"
        )

        // Step 2: Record a real benchmark
        planner.recordBenchmark(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            result: BenchmarkResult(
                engineName: "llama.cpp",
                tokensPerSecond: 72.5,
                ttftMs: 150.0,
                memoryMb: 480.0
            ),
            additionalRuntimes: [bare]
        )

        // Step 3: Resolve AFTER benchmark — should use cached benchmark
        let selectionAfter = await planner.resolve(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [bare]
        )

        XCTAssertEqual(
            selectionAfter.locality, .local,
            "After benchmark write, resolution must use cached benchmark for local"
        )
        XCTAssertEqual(
            selectionAfter.source, "cache",
            "Source must be 'cache' when using a cached benchmark"
        )
        XCTAssertEqual(
            selectionAfter.engine, "llama.cpp",
            "Cached benchmark engine must match what was recorded"
        )
        XCTAssertTrue(
            selectionAfter.reason.contains("72.5"),
            "Reason should reference the cached benchmark tok/s: \(selectionAfter.reason)"
        )
    }

    /// Benchmark cache for one model must not leak into resolution for a
    /// different model.
    func testBenchmarkCacheIsModelScoped() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let bare = bareRuntime(engine: "mlx")

        // Record benchmark for model A
        planner.recordBenchmark(
            model: "model-a",
            capability: "text",
            routingPolicy: "local_first",
            result: BenchmarkResult(
                engineName: "mlx",
                tokensPerSecond: 100.0,
                ttftMs: 50.0,
                memoryMb: 300.0
            ),
            additionalRuntimes: [bare]
        )

        // Resolve for model B — should NOT use model A's benchmark
        let selection = await planner.resolve(
            model: "model-b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [bare]
        )

        XCTAssertNotEqual(
            selection.source, "cache",
            "Benchmark cache for model-a must not be used for model-b"
        )
        XCTAssertEqual(
            selection.locality, .cloud,
            "Without matching benchmark or evidence, should fall back to cloud"
        )
    }

    /// Benchmark cache for one capability must not apply to a different capability.
    func testBenchmarkCacheIsCapabilityScoped() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let bare = bareRuntime(engine: "whisper.cpp")

        // Record benchmark for audio_transcription
        planner.recordBenchmark(
            model: "whisper-base",
            capability: "audio_transcription",
            routingPolicy: "local_first",
            result: BenchmarkResult(
                engineName: "whisper.cpp",
                tokensPerSecond: 0.0,
                ttftMs: 200.0,
                memoryMb: 150.0
            ),
            additionalRuntimes: [bare]
        )

        // Resolve for text capability — should NOT use audio benchmark
        let selection = await planner.resolve(
            model: "whisper-base",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [bare]
        )

        XCTAssertNotEqual(
            selection.source, "cache",
            "Audio benchmark cache must not apply to text capability"
        )
    }

    // MARK: - Cross-cutting: evidence vs framework detection

    /// Verify the core invariant that framework availability alone (without
    /// model evidence) does NOT prove model capability. This is the most
    /// important product semantic the planner enforces.
    func testFrameworkDetectionAloneIsInsufficient() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // MLX framework is installed and available, but has NO model evidence
        let frameworkOnly = InstalledRuntime(
            engine: "mlx",
            version: "0.30.0",
            available: true,
            accelerator: "metal"
            // No metadata → no model/capability evidence
        )

        // Also add a model-capable runtime for a DIFFERENT model
        let wrongModelEvidence = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "phi-3",
            capabilities: ["text"]
        )

        let selection = await planner.resolve(
            model: "llama-70b", // Neither runtime has evidence for this model
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [frameworkOnly, wrongModelEvidence]
        )

        XCTAssertEqual(
            selection.locality, .cloud,
            "Must fall back to cloud when no runtime has evidence for the requested model"
        )
        XCTAssertNil(
            selection.engine,
            "Engine must be nil when no local match exists"
        )
    }
}

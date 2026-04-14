import Foundation
import XCTest
@testable import Octomil

final class RuntimeBenchmarkReporterTests: XCTestCase {

    private var tempDir: URL!
    private var store: RuntimePlannerStore!
    private var planner: RuntimePlanner!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-reporter-test-\(UUID().uuidString)", isDirectory: true)
        store = RuntimePlannerStore(cacheDirectory: tempDir)
        planner = RuntimePlanner(store: store, client: nil)
        RuntimeBenchmarkReporter.shared.configure(planner: planner, routingPolicy: "local_first")
    }

    override func tearDown() {
        RuntimeBenchmarkReporter.shared.reset()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Basic Reporting

    func testReportStoresBenchmarkInPlannerCache() async {
        let evidence = InstalledRuntime.modelCapable(
            engine: "mlx-lm",
            model: "test-model",
            capabilities: ["text"],
            accelerator: "metal"
        )

        RuntimeBenchmarkReporter.shared.report(
            model: "test-model",
            capability: "text",
            engineName: "mlx-lm",
            tokensPerSecond: 42.5,
            ttftMs: 150.0,
            memoryMb: 256.0,
            additionalRuntimes: [evidence]
        )

        // Verify the planner can now resolve from the cached benchmark
        let selection = await planner.resolve(
            model: "test-model",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.engine, "mlx-lm")
        XCTAssertEqual(selection.source, "cache")
    }

    // MARK: - No Planner Configured

    func testReportWithoutPlannerDoesNotCrash() {
        RuntimeBenchmarkReporter.shared.reset()

        // Should not crash even without a planner
        RuntimeBenchmarkReporter.shared.report(
            model: "orphan-model",
            capability: "text",
            engineName: "llama.cpp",
            tokensPerSecond: 100.0,
            ttftMs: 50.0,
            memoryMb: 512.0
        )
    }

    // MARK: - Private Policy

    func testReportWithPrivatePolicyStoresLocally() async {
        RuntimeBenchmarkReporter.shared.configure(planner: planner, routingPolicy: "private")

        let evidence = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "private-model",
            capabilities: ["text"]
        )

        RuntimeBenchmarkReporter.shared.report(
            model: "private-model",
            capability: "text",
            engineName: "llama.cpp",
            tokensPerSecond: 55.0,
            ttftMs: 200.0,
            memoryMb: 1024.0,
            additionalRuntimes: [evidence]
        )

        // Verify the benchmark is stored locally
        let selection = await planner.resolve(
            model: "private-model",
            capability: "text",
            routingPolicy: "private",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.source, "cache")
    }

    // MARK: - Reset

    func testResetClearsPlannerReference() {
        RuntimeBenchmarkReporter.shared.reset()

        // After reset, reporting should be a no-op (no crash)
        RuntimeBenchmarkReporter.shared.report(
            model: "post-reset-model",
            capability: "text",
            engineName: "coreml",
            tokensPerSecond: 30.0,
            ttftMs: 300.0,
            memoryMb: 128.0
        )
    }

    // MARK: - Audio Throughput

    func testReportAudioThroughput() async {
        let evidence = InstalledRuntime.modelCapable(
            engine: "whisper.cpp",
            model: "whisper-base",
            capabilities: ["audio_transcription"],
            accelerator: "metal"
        )

        // Audio throughput ratio: 5x realtime
        RuntimeBenchmarkReporter.shared.report(
            model: "whisper-base",
            capability: "audio_transcription",
            engineName: "whisper.cpp",
            tokensPerSecond: 5.0, // throughput ratio, not tokens
            ttftMs: 2000.0,
            memoryMb: 256.0,
            additionalRuntimes: [evidence]
        )

        let selection = await planner.resolve(
            model: "whisper-base",
            capability: "audio_transcription",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.engine, "whisper.cpp")
        XCTAssertEqual(selection.source, "cache")
    }
}

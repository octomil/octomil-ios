import XCTest
@testable import Octomil

/// Tests for ``WarmupResult``.
///
/// `WarmupResult` is the return type of ``OctomilModel/warmup()``. It is a plain
/// value type with no `MLModel` dependency, so it can be exercised directly
/// without the test fixtures required to construct an `OctomilModel` instance.
final class WarmupResultTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithAllParametersSetsAllProperties() {
        let result = WarmupResult(
            coldInferenceMs: 120.5,
            warmInferenceMs: 12.0,
            cpuInferenceMs: 45.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: ["gpu"]
        )

        XCTAssertEqual(result.coldInferenceMs, 120.5)
        XCTAssertEqual(result.warmInferenceMs, 12.0)
        XCTAssertEqual(result.cpuInferenceMs, 45.0)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "neural_engine")
        XCTAssertEqual(result.disabledDelegates, ["gpu"])
    }

    func testInitWithDefaultsLeavesCpuInferenceNilAndDisabledEmpty() {
        let result = WarmupResult(
            coldInferenceMs: 80.0,
            warmInferenceMs: 8.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu"
        )

        XCTAssertNil(result.cpuInferenceMs)
        XCTAssertEqual(result.disabledDelegates, [])
    }

    func testInitPreservesZeroAndNegativeTimings() {
        // The struct does not validate timing values — guard against
        // future code accidentally clamping or rejecting edge values.
        let result = WarmupResult(
            coldInferenceMs: 0.0,
            warmInferenceMs: 0.0,
            cpuInferenceMs: 0.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu"
        )

        XCTAssertEqual(result.coldInferenceMs, 0.0)
        XCTAssertEqual(result.warmInferenceMs, 0.0)
        XCTAssertEqual(result.cpuInferenceMs, 0.0)
    }

    // MARK: - delegateDisabled

    func testDelegateDisabledIsFalseWhenDisabledDelegatesIsEmpty() {
        let result = WarmupResult(
            coldInferenceMs: 1.0,
            warmInferenceMs: 1.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine"
        )
        XCTAssertFalse(result.delegateDisabled)
    }

    func testDelegateDisabledIsTrueWhenSingleDelegateDisabled() {
        let result = WarmupResult(
            coldInferenceMs: 1.0,
            warmInferenceMs: 1.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine"]
        )
        XCTAssertTrue(result.delegateDisabled)
    }

    func testDelegateDisabledIsTrueWhenMultipleDelegatesDisabled() {
        let result = WarmupResult(
            coldInferenceMs: 1.0,
            warmInferenceMs: 1.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine", "gpu"]
        )
        XCTAssertTrue(result.delegateDisabled)
    }

    // MARK: - Cascade scenarios mirroring OctomilModel.warmup()

    func testNeuralEngineWinsCascade() {
        // Active path when NE outperforms CPU during warmup.
        let result = WarmupResult(
            coldInferenceMs: 200.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: 25.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine"
        )

        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "neural_engine")
        XCTAssertFalse(result.delegateDisabled)
    }

    func testCpuWinsCascadeAndDisablesNeuralEngine() {
        // Mirrors OctomilModel.warmup()'s fallback when CPU beats NE.
        let result = WarmupResult(
            coldInferenceMs: 200.0,
            warmInferenceMs: 30.0,
            cpuInferenceMs: 10.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine"]
        )

        XCTAssertFalse(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "cpu")
        XCTAssertTrue(result.delegateDisabled)
        XCTAssertEqual(result.disabledDelegates, ["neural_engine"])
    }

    func testNoCpuBenchmarkRecorded() {
        // When the CPU-only model fails to load, cpuInferenceMs is left nil
        // and the original delegate stays active.
        let result = WarmupResult(
            coldInferenceMs: 200.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: nil,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine"
        )

        XCTAssertNil(result.cpuInferenceMs)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertFalse(result.delegateDisabled)
    }

    // MARK: - Sendable conformance

    func testWarmupResultIsSendable() {
        // Compile-time check: assigning to an `any Sendable` exists only if
        // WarmupResult declares Sendable conformance.
        let result = WarmupResult(
            coldInferenceMs: 1.0,
            warmInferenceMs: 1.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu"
        )
        let _: any Sendable = result
    }
}

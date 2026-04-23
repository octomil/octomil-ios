import Foundation
import XCTest

@testable import Octomil

// MARK: - Test Doubles

/// Runtime checker that reports specific engines as unavailable.
private struct StubRuntimeChecker: AttemptRuntimeChecker {
    let unavailableEngines: Set<String>

    func check(engine: String?, locality: String) -> (available: Bool, reasonCode: String?) {
        guard let engine else {
            // Cloud candidates have no engine — always available
            return (true, nil)
        }
        let canonical = RuntimeEngineID.canonical(engine)
        if unavailableEngines.contains(canonical) {
            return (false, "engine_not_installed")
        }
        return (true, nil)
    }
}

/// Artifact checker that reports specific artifact IDs as failed.
private struct StubArtifactChecker: AttemptArtifactChecker {
    let failedArtifactIds: Set<String>

    func check(artifactPlan: RuntimeArtifactPlan) -> (ok: Bool, cacheStatus: String, reasonCode: String?) {
        if let id = artifactPlan.artifactId, failedArtifactIds.contains(id) {
            return (false, "unavailable", "digest_mismatch")
        }
        return (true, "hit", nil)
    }
}

/// Output quality gate evaluator stub for tests.
private struct StubOutputQualityEvaluator: OutputQualityGateEvaluator {
    let name: String = "stub_quality_evaluator"
    let failingGates: Set<String>
    let scores: [String: Double]

    init(failingGates: Set<String> = [], scores: [String: Double] = [:]) {
        self.failingGates = failingGates
        self.scores = scores
    }

    func evaluate(gate: CandidateGate, response: Any) async -> GateEvaluationResult {
        let shouldFail = failingGates.contains(gate.code)
        return GateEvaluationResult(
            passed: !shouldFail,
            score: scores[gate.code],
            reasonCode: shouldFail ? "\(gate.code)_failed" : nil
        )
    }
}

/// Gate evaluator that fails specific gate codes.
private struct StubGateEvaluator: AttemptGateEvaluator {
    /// Gate codes that should fail, mapped to observed/threshold values.
    let failingGates: [String: (observed: Double, threshold: Double)]

    func evaluate(gate: CandidateGate, engine: String?, locality: String) -> GateResult {
        if let fail = failingGates[gate.code] {
            return GateResult(
                code: gate.code,
                status: .failed,
                observedNumber: fail.observed,
                thresholdNumber: fail.threshold,
                reasonCode: "\(gate.code)_exceeded"
            )
        }
        return GateResult(
            code: gate.code,
            status: .passed,
            observedNumber: gate.thresholdNumber.map { $0 * 0.5 },
            thresholdNumber: gate.thresholdNumber
        )
    }
}

// MARK: - Helper Factories

private func makeLocalCandidate(
    engine: String = "mlx-lm",
    priority: Int = 0,
    artifactId: String? = "art_001",
    digest: String? = "sha256:abc123",
    gates: [CandidateGate] = []
) -> AttemptCandidateInput {
    let artifact: RuntimeArtifactPlan?
    if let artifactId {
        artifact = RuntimeArtifactPlan(
            modelId: "gemma-2b",
            artifactId: artifactId,
            modelVersion: "1.0.0",
            format: "gguf",
            digest: digest
        )
    } else {
        artifact = nil
    }

    return AttemptCandidateInput(
        candidate: RuntimeCandidatePlan(
            locality: .local,
            priority: priority,
            confidence: 0.95,
            reason: "server recommended",
            engine: engine,
            artifact: artifact
        ),
        gates: gates
    )
}

private func makeCloudCandidate(
    priority: Int = 1,
    gates: [CandidateGate] = []
) -> AttemptCandidateInput {
    AttemptCandidateInput(
        candidate: RuntimeCandidatePlan(
            locality: .cloud,
            priority: priority,
            confidence: 0.9,
            reason: "cloud fallback"
        ),
        gates: gates
    )
}

// MARK: - Tests

final class CandidateAttemptRunnerTests: XCTestCase {

    // MARK: - Single candidate, all gates pass

    func testSingleLocalCandidateAllGatesPass() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", thresholdNumber: 10.0, source: "server"),
            CandidateGate(code: "max_ttft_ms", thresholdNumber: 2000, source: "server"),
            CandidateGate(code: "min_free_memory_bytes", thresholdNumber: 500_000_000, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded, "Should succeed with a single passing candidate")
        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertEqual(result.selectedAttempt?.stage, .inference)
        XCTAssertEqual(result.selectedAttempt?.locality, "local")
        XCTAssertEqual(result.selectedAttempt?.mode, "sdk_runtime")
        XCTAssertEqual(result.selectedAttempt?.engine, "mlx-lm")
        XCTAssertEqual(result.selectedAttempt?.index, 0)
        XCTAssertFalse(result.fallbackUsed)
        XCTAssertNil(result.fallbackTrigger)
        XCTAssertEqual(result.attempts.count, 1)

        // Verify gate results include runtime_available + artifact_verified + the 3 custom gates
        let gateResults = result.selectedAttempt!.gateResults
        XCTAssertTrue(gateResults.count >= 5, "Expected at least 5 gate results, got \(gateResults.count)")

        let gateCodes = gateResults.map(\.code)
        XCTAssertTrue(gateCodes.contains("runtime_available"))
        XCTAssertTrue(gateCodes.contains("artifact_verified"))
        XCTAssertTrue(gateCodes.contains("min_tokens_per_second"))
        XCTAssertTrue(gateCodes.contains("max_ttft_ms"))
        XCTAssertTrue(gateCodes.contains("min_free_memory_bytes"))

        // All should be passed
        for gr in gateResults {
            XCTAssertEqual(gr.status, .passed, "Gate \(gr.code) should pass")
        }
    }

    // MARK: - Local runtime unavailable, fallback to cloud

    func testLocalRuntimeUnavailableFallsBackToCloud() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let rtChecker = StubRuntimeChecker(unavailableEngines: ["mlx-lm"])

        let candidates = [
            makeLocalCandidate(engine: "mlx-lm"),
            makeCloudCandidate(),
        ]

        let result = runner.run(
            candidates: candidates,
            runtimeChecker: rtChecker
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 2)

        // First attempt failed at prepare
        let first = result.attempts[0]
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.status, .failed)
        XCTAssertEqual(first.stage, .prepare)
        XCTAssertEqual(first.locality, "local")
        XCTAssertEqual(first.reason.code, "runtime_unavailable")

        // Second attempt selected (cloud)
        let second = result.attempts[1]
        XCTAssertEqual(second.index, 1)
        XCTAssertEqual(second.status, .selected)
        XCTAssertEqual(second.stage, .inference)
        XCTAssertEqual(second.locality, "cloud")
        XCTAssertEqual(second.mode, "hosted_gateway")

        // Fallback metadata
        XCTAssertTrue(result.fallbackUsed)
        XCTAssertNotNil(result.fallbackTrigger)
        XCTAssertEqual(result.fallbackTrigger?.code, "runtime_unavailable")
        XCTAssertEqual(result.fallbackTrigger?.stage, "prepare")
        XCTAssertEqual(result.fromAttempt, 0)
        XCTAssertEqual(result.toAttempt, 1)
    }

    // MARK: - Gate failure triggers fallback

    func testGateFailureTriggersFallback() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let gateEval = StubGateEvaluator(failingGates: [
            "max_ttft_ms": (observed: 3200, threshold: 2000),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "max_ttft_ms", required: true, thresholdNumber: 2000, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(engine: "llama.cpp", gates: gates),
            makeCloudCandidate(),
        ]

        let result = runner.run(
            candidates: candidates,
            gateEvaluator: gateEval
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 2)

        // First attempt failed at gate stage
        let first = result.attempts[0]
        XCTAssertEqual(first.status, .failed)
        XCTAssertEqual(first.stage, .gate)
        XCTAssertEqual(first.reason.code, "gate_failed")

        // The gate result should carry observed/threshold numbers
        let ttftGate = first.gateResults.first { $0.code == "max_ttft_ms" }
        XCTAssertNotNil(ttftGate)
        XCTAssertEqual(ttftGate?.status, .failed)
        XCTAssertEqual(ttftGate?.observedNumber, 3200)
        XCTAssertEqual(ttftGate?.thresholdNumber, 2000)

        // Second attempt selected
        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
        XCTAssertTrue(result.fallbackUsed)
        XCTAssertEqual(result.fallbackTrigger?.code, "gate_failed")
        XCTAssertEqual(result.fallbackTrigger?.stage, "gate")
    }

    // MARK: - Private/local_only policy: no fallback

    func testPrivateNoFallbackFails() {
        let runner = CandidateAttemptRunner(fallbackAllowed: false)
        let rtChecker = StubRuntimeChecker(unavailableEngines: ["mlx-lm"])

        let candidates = [
            makeLocalCandidate(engine: "mlx-lm"),
            makeCloudCandidate(),
        ]

        let result = runner.run(
            candidates: candidates,
            runtimeChecker: rtChecker
        )

        XCTAssertFalse(result.succeeded, "Should fail when fallback is not allowed")
        XCTAssertNil(result.selectedAttempt)
        XCTAssertEqual(result.attempts.count, 1, "Should stop after first failure")
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertFalse(result.fallbackUsed)
        XCTAssertNil(result.fallbackTrigger)
    }

    // MARK: - Attempt indices sequential

    func testAttemptIndicesSequential() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let rtChecker = StubRuntimeChecker(unavailableEngines: ["coreml", "llama.cpp"])

        let candidates = [
            makeLocalCandidate(engine: "coreml", priority: 0),
            makeLocalCandidate(engine: "llama.cpp", priority: 1),
            makeCloudCandidate(priority: 2),
        ]

        let result = runner.run(
            candidates: candidates,
            runtimeChecker: rtChecker
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 3)

        for (i, attempt) in result.attempts.enumerated() {
            XCTAssertEqual(attempt.index, i, "Attempt at position \(i) has wrong index \(attempt.index)")
        }
    }

    // MARK: - JSON encoding matches contract shape

    func testOutputEncodesCorrectly() throws {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        let attempt = try XCTUnwrap(result.selectedAttempt)

        // Encode the attempt as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(attempt)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify required fields from route_attempt.schema.json
        XCTAssertEqual(json["index"] as? Int, 0)
        XCTAssertEqual(json["locality"] as? String, "local")
        XCTAssertEqual(json["mode"] as? String, "sdk_runtime")
        XCTAssertEqual(json["engine"] as? String, "mlx-lm")
        XCTAssertEqual(json["status"] as? String, "selected")
        XCTAssertEqual(json["stage"] as? String, "inference")

        // Verify reason object shape
        let reason = try XCTUnwrap(json["reason"] as? [String: Any])
        XCTAssertNotNil(reason["code"])
        XCTAssertNotNil(reason["message"])

        // Verify gate_results is an array
        let gateResultsJSON = try XCTUnwrap(json["gate_results"] as? [[String: Any]])
        XCTAssertFalse(gateResultsJSON.isEmpty)
        for gr in gateResultsJSON {
            XCTAssertNotNil(gr["code"], "gate_result must have 'code'")
            XCTAssertNotNil(gr["status"], "gate_result must have 'status'")
        }

        // Verify artifact shape when present
        let artifactJSON = try XCTUnwrap(json["artifact"] as? [String: Any])
        XCTAssertEqual(artifactJSON["id"] as? String, "art_001")
        XCTAssertEqual(artifactJSON["digest"] as? String, "sha256:abc123")
        let cache = try XCTUnwrap(artifactJSON["cache"] as? [String: Any])
        XCTAssertEqual(cache["status"] as? String, "hit")
        XCTAssertEqual(cache["managed_by"] as? String, "octomil")
    }

    // MARK: - Artifact verification failure

    func testArtifactVerificationFailureFallsBack() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let artChecker = StubArtifactChecker(failedArtifactIds: ["art_bad"])

        let candidates = [
            makeLocalCandidate(engine: "llama.cpp", artifactId: "art_bad"),
            makeCloudCandidate(),
        ]

        let result = runner.run(
            candidates: candidates,
            artifactChecker: artChecker
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 2)

        let first = result.attempts[0]
        XCTAssertEqual(first.status, .failed)
        XCTAssertEqual(first.stage, .verify)
        XCTAssertEqual(first.reason.code, "artifact_verification_failed")

        let artGate = first.gateResults.first { $0.code == "artifact_verified" }
        XCTAssertEqual(artGate?.status, .failed)
        XCTAssertEqual(artGate?.reasonCode, "digest_mismatch")

        XCTAssertTrue(result.fallbackUsed)
        XCTAssertEqual(result.fallbackTrigger?.code, "artifact_verification_failed")
        XCTAssertEqual(result.fallbackTrigger?.stage, "verify")

        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
    }

    // MARK: - Optional (non-required) gate failure does not block

    func testNonRequiredGateFailureDoesNotBlock() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let gateEval = StubGateEvaluator(failingGates: [
            "benchmark_fresh": (observed: 7200, threshold: 3600),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "benchmark_fresh", required: false, thresholdNumber: 3600, windowSeconds: 3600, source: "sdk"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        let result = runner.run(
            candidates: candidates,
            gateEvaluator: gateEval
        )

        XCTAssertTrue(result.succeeded, "Non-required gate failure should not block selection")
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertFalse(result.fallbackUsed)
    }

    // MARK: - Empty candidates list

    func testEmptyCandidatesReturnsNoSelection() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let result = runner.run(candidates: [])

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.selectedAttempt)
        XCTAssertTrue(result.attempts.isEmpty)
        XCTAssertFalse(result.fallbackUsed)
    }

    // MARK: - Cloud candidate with no engine

    func testCloudCandidateSelectedDirectly() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let candidates = [makeCloudCandidate()]

        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
        XCTAssertEqual(result.selectedAttempt?.mode, "hosted_gateway")
        XCTAssertNil(result.selectedAttempt?.engine)
        XCTAssertNil(result.selectedAttempt?.artifact)
    }

    // MARK: - Multiple gate failures on single candidate

    func testMultipleGateFailuresRecordedBeforeFirstRequired() {
        let runner = CandidateAttemptRunner(fallbackAllowed: false)
        let gateEval = StubGateEvaluator(failingGates: [
            "min_free_memory_bytes": (observed: 100_000_000, threshold: 500_000_000),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
            CandidateGate(code: "min_free_memory_bytes", required: true, thresholdNumber: 500_000_000, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        let result = runner.run(
            candidates: candidates,
            gateEvaluator: gateEval
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.attempts.count, 1)

        let attempt = result.attempts[0]
        XCTAssertEqual(attempt.stage, .gate)

        // min_tokens_per_second passes, then min_free_memory_bytes fails
        let memGate = attempt.gateResults.first { $0.code == "min_free_memory_bytes" }
        XCTAssertNotNil(memGate)
        XCTAssertEqual(memGate?.status, .failed)
        XCTAssertEqual(memGate?.observedNumber, 100_000_000)
        XCTAssertEqual(memGate?.thresholdNumber, 500_000_000)
    }

    // MARK: - Runtime available and artifact_verified gates are not double-evaluated

    func testRuntimeAndArtifactGatesNotDoubleEvaluated() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        // Even if these are in the gates list, they should be skipped
        // because they are evaluated in the prepare/verify stages.
        let gates: [CandidateGate] = [
            CandidateGate(code: "runtime_available", required: true, source: "server"),
            CandidateGate(code: "artifact_verified", required: true, source: "server"),
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded)

        // Should have runtime_available, artifact_verified, and min_tokens_per_second
        // but runtime_available and artifact_verified come from the stage checks, not from gate evaluation
        let gateResults = result.selectedAttempt!.gateResults
        let rtCodes = gateResults.filter { $0.code == "runtime_available" }
        let artCodes = gateResults.filter { $0.code == "artifact_verified" }
        XCTAssertEqual(rtCodes.count, 1, "runtime_available should appear exactly once")
        XCTAssertEqual(artCodes.count, 1, "artifact_verified should appear exactly once")
    }

    // MARK: - toRouteMetadataFields produces valid structure

    func testToRouteMetadataFieldsStructure() throws {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let rtChecker = StubRuntimeChecker(unavailableEngines: ["mlx-lm"])

        let candidates = [
            makeLocalCandidate(engine: "mlx-lm"),
            makeCloudCandidate(),
        ]

        let result = runner.run(
            candidates: candidates,
            runtimeChecker: rtChecker
        )

        let fields = result.toRouteMetadataFields()

        let attempts = try XCTUnwrap(fields["attempts"] as? [[String: Any]])
        XCTAssertEqual(attempts.count, 2)

        let fallback = try XCTUnwrap(fields["fallback"] as? [String: Any])
        XCTAssertEqual(fallback["used"] as? Bool, true)
        XCTAssertEqual(fallback["from_attempt"] as? Int, 0)
        XCTAssertEqual(fallback["to_attempt"] as? Int, 1)

        let trigger = try XCTUnwrap(fallback["trigger"] as? [String: Any])
        XCTAssertEqual(trigger["code"] as? String, "runtime_unavailable")
        XCTAssertEqual(trigger["stage"] as? String, "prepare")
    }

    // MARK: - Mode derivation

    func testModeForLocality() {
        XCTAssertEqual(CandidateAttemptRunner.modeForLocality(.local), "sdk_runtime")
        XCTAssertEqual(CandidateAttemptRunner.modeForLocality(.cloud), "hosted_gateway")
    }

    // MARK: - All 12 gate codes are covered by the enum

    func testAllGateCodesCovered() {
        let expected: Set<String> = [
            "artifact_verified", "runtime_available", "model_loads",
            "context_fits", "modality_supported", "tool_support",
            "min_tokens_per_second", "max_ttft_ms", "max_error_rate",
            "min_free_memory_bytes", "min_free_storage_bytes", "benchmark_fresh",
            "schema_valid", "tool_call_valid", "safety_passed",
            "evaluator_score_min", "json_parseable", "max_refusal_rate",
        ]
        let actual = Set(GateCode.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected, "GateCode enum must cover all 18 contract gate codes")
    }

    // MARK: - Local candidate without artifact skips verify stage

    func testLocalCandidateWithoutArtifactSkipsVerify() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let candidates = [makeLocalCandidate(artifactId: nil)]

        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded)
        let gateResults = result.selectedAttempt!.gateResults
        let artCodes = gateResults.filter { $0.code == "artifact_verified" }
        XCTAssertTrue(artCodes.isEmpty, "No artifact_verified gate should be emitted when no artifact is present")
    }

    // MARK: - Sendable conformance

    func testRunnerIsSendable() {
        // Compile-time check: CandidateAttemptRunner can be sent across concurrency boundaries.
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let _: any Sendable = runner
        XCTAssertTrue(true, "CandidateAttemptRunner compiles as Sendable")
    }

    // MARK: - Three candidates, first two fail, third selected

    func testThreeCandidatesLastSelected() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let rtChecker = StubRuntimeChecker(unavailableEngines: ["coreml"])
        let gateEval = StubGateEvaluator(failingGates: [
            "min_free_memory_bytes": (observed: 100_000_000, threshold: 500_000_000),
        ])

        let memGate = CandidateGate(
            code: "min_free_memory_bytes",
            required: true,
            thresholdNumber: 500_000_000,
            source: "server"
        )

        let candidates = [
            makeLocalCandidate(engine: "coreml", priority: 0),
            makeLocalCandidate(engine: "llama.cpp", priority: 1, gates: [memGate]),
            makeCloudCandidate(priority: 2),
        ]

        let result = runner.run(
            candidates: candidates,
            runtimeChecker: rtChecker,
            gateEvaluator: gateEval
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 3)

        // First: runtime unavailable
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .prepare)
        XCTAssertEqual(result.attempts[0].engine, "coreml")

        // Second: gate failed
        XCTAssertEqual(result.attempts[1].status, .failed)
        XCTAssertEqual(result.attempts[1].stage, .gate)
        XCTAssertEqual(result.attempts[1].engine, "llama.cpp")

        // Third: cloud selected
        XCTAssertEqual(result.attempts[2].status, .selected)
        XCTAssertEqual(result.attempts[2].locality, "cloud")

        XCTAssertTrue(result.fallbackUsed)
        // Trigger from first failure
        XCTAssertEqual(result.fallbackTrigger?.code, "runtime_unavailable")
        XCTAssertEqual(result.fromAttempt, 0)
        XCTAssertEqual(result.toAttempt, 2)
    }

    // MARK: - Engine canonicalization

    func testEngineCanonicalizedInAttempt() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let candidate = AttemptCandidateInput(
            candidate: RuntimeCandidatePlan(
                locality: .local,
                priority: 0,
                confidence: 0.9,
                reason: "test",
                engine: "llamacpp"  // Non-canonical alias
            ),
            gates: []
        )

        let result = runner.run(candidates: [candidate])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.selectedAttempt?.engine, "llama.cpp", "Engine should be canonicalized")
    }

    // MARK: - Output quality gates are skipped in run()

    func testOutputQualityGatesSkippedInRun() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let gateEval = StubGateEvaluator(failingGates: [
            "schema_valid": (observed: 0, threshold: 1),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server",
                          gateClass: "output_quality", evaluationPhase: "post_inference"),
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates, gateEvaluator: gateEval)

        XCTAssertTrue(result.succeeded, "Output quality gates should be skipped in run()")
        let gateCodes = result.selectedAttempt!.gateResults.map(\.code)
        XCTAssertFalse(gateCodes.contains("schema_valid"),
                       "schema_valid should not be evaluated in run()")
        XCTAssertTrue(gateCodes.contains("min_tokens_per_second"))
    }

    // MARK: - Output quality gate failure before output → fallback

    func testOutputQualityGateFailureBeforeOutputTriggersFallback() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: false)
        let qualityEval = StubOutputQualityEvaluator(failingGates: ["schema_valid"])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server",
                          gateClass: "output_quality", evaluationPhase: "post_inference"),
        ]

        let candidates = [
            makeLocalCandidate(engine: "mlx-lm", gates: gates),
            makeCloudCandidate(),
        ]

        let result: AttemptInferenceResult<String> = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: qualityEval,
            firstOutputEmitted: { false },
            executeCandidate: { _, _ in "test response" }
        )

        // First candidate should fail at output_quality stage
        XCTAssertTrue(result.attempts.count >= 2,
                      "Expected at least 2 attempts, got \(result.attempts.count)")
        let firstAttempt = result.attempts[0]
        XCTAssertEqual(firstAttempt.status, .failed)
        XCTAssertEqual(firstAttempt.stage, .outputQuality)
        XCTAssertEqual(firstAttempt.reason.code, "output_quality_gate_failed")

        // Should have fallen back to cloud
        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
        XCTAssertTrue(result.fallbackUsed)
        XCTAssertEqual(result.fallbackTrigger?.code, "output_quality_gate_failed")
        XCTAssertEqual(result.fallbackTrigger?.gateCode, "schema_valid")
        XCTAssertEqual(result.fallbackTrigger?.gateClass, "output_quality")
        XCTAssertEqual(result.fallbackTrigger?.evaluationPhase, "post_inference")
        XCTAssertEqual(result.fallbackTrigger?.outputVisibleBeforeFailure, false)
    }

    // MARK: - Output quality gate failure after first token → NO fallback

    func testOutputQualityGateFailureAfterFirstTokenNoFallback() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: true)
        let qualityEval = StubOutputQualityEvaluator(failingGates: ["schema_valid"])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server",
                          gateClass: "output_quality", evaluationPhase: "post_inference"),
        ]

        let candidates = [
            makeLocalCandidate(engine: "mlx-lm", gates: gates),
            makeCloudCandidate(),
        ]

        let result: AttemptInferenceResult<String> = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: qualityEval,
            firstOutputEmitted: { true },  // Output already emitted
            executeCandidate: { _, _ in "test response" }
        )

        // Should NOT fallback — output was already visible
        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.locality, "local")
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertEqual(result.selectedAttempt?.status, .selected)

        // The schema_valid gate result should still be present (recorded)
        let schemaGate = result.selectedAttempt!.gateResults.first { $0.code == "schema_valid" }
        XCTAssertNotNil(schemaGate)
        XCTAssertEqual(schemaGate?.status, .failed)
    }

    // MARK: - Advisory quality gate failure → no disqualification

    func testAdvisoryQualityGateFailureNoDisqualification() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: false)
        let qualityEval = StubOutputQualityEvaluator(
            failingGates: ["evaluator_score_min"],
            scores: ["evaluator_score_min": 0.3]
        )

        let gates: [CandidateGate] = [
            CandidateGate(code: "evaluator_score_min", required: false, thresholdNumber: 0.8,
                          source: "server", gateClass: "output_quality",
                          evaluationPhase: "post_inference"),
        ]

        let candidates = [makeLocalCandidate(engine: "mlx-lm", gates: gates)]

        let result: AttemptInferenceResult<String> = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: qualityEval,
            firstOutputEmitted: { false },
            executeCandidate: { _, _ in "test response" }
        )

        XCTAssertNotNil(result.selectedAttempt, "Advisory gate failure should not disqualify")
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertFalse(result.fallbackUsed)

        // Gate result should be recorded
        let evalGate = result.selectedAttempt!.gateResults.first { $0.code == "evaluator_score_min" }
        XCTAssertNotNil(evalGate)
        XCTAssertEqual(evalGate?.status, .failed)
        XCTAssertEqual(evalGate?.observedNumber, 0.3)
    }

    // MARK: - Private policy prevents fallback on quality gate failure

    func testPrivatePolicyPreventsQualityGateFallback() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: false, streaming: false)
        let qualityEval = StubOutputQualityEvaluator(failingGates: ["schema_valid"])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server",
                          gateClass: "output_quality", evaluationPhase: "post_inference"),
        ]

        let candidates = [
            makeLocalCandidate(engine: "mlx-lm", gates: gates),
            makeCloudCandidate(),
        ]

        let result: AttemptInferenceResult<String> = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: qualityEval,
            firstOutputEmitted: { false },
            executeCandidate: { _, _ in "test response" }
        )

        // Private policy: no fallback allowed, should fail
        XCTAssertNil(result.selectedAttempt, "Private policy should not fall back on quality gate failure")
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertEqual(result.attempts[0].stage, .outputQuality)
        XCTAssertFalse(result.fallbackUsed)
    }

    // MARK: - Unknown required gate fails closed

    func testUnknownRequiredGateFailsClosed() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let gateEval = StubGateEvaluator(failingGates: [
            "unknown_future_gate": (observed: 0, threshold: 1),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "unknown_future_gate", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = runner.run(candidates: candidates, gateEvaluator: gateEval)

        // Unknown gate defaults to pre_inference (fail-closed) — should trigger fallback
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 2)
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .gate)
        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
    }

    func testRequiredDeviceGateFailsClosedAndFallsBack() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let gates: [CandidateGate] = [
            CandidateGate(code: "require_wifi", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 2)
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .gate)
        let failedGate = result.attempts[0].gateResults.first { $0.code == "require_wifi" }
        XCTAssertEqual(failedGate?.reasonCode, "network_state_unavailable")
        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
    }

    // MARK: - All gate results include gateClass and evaluationPhase

    func testAllGateResultsIncludeClassAndPhase() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
            CandidateGate(code: "max_ttft_ms", required: true, thresholdNumber: 2000, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded)
        let gateResults = result.selectedAttempt!.gateResults

        for gr in gateResults {
            XCTAssertNotNil(gr.gateClass, "Gate \(gr.code) should have gateClass set")
            XCTAssertNotNil(gr.evaluationPhase, "Gate \(gr.code) should have evaluationPhase set")
        }

        // Verify specific classifications
        let rtGate = gateResults.first { $0.code == "runtime_available" }
        XCTAssertEqual(rtGate?.gateClass, "readiness")
        XCTAssertEqual(rtGate?.evaluationPhase, "pre_inference")

        let tpsGate = gateResults.first { $0.code == "min_tokens_per_second" }
        XCTAssertEqual(tpsGate?.gateClass, "performance")
        XCTAssertEqual(tpsGate?.evaluationPhase, "pre_inference")
    }

    // MARK: - GATE_CLASSIFICATION covers all 18 gate codes

    func testGateClassificationCoversAllCodes() {
        for gateCode in GateCode.allCases {
            XCTAssertNotNil(GATE_CLASSIFICATION[gateCode.rawValue],
                           "GATE_CLASSIFICATION must include \(gateCode.rawValue)")
        }
    }

    // MARK: - Output quality gates use explicit gate_class from server

    func testOutputQualityGateUsesExplicitClassFromServer() {
        let gate = CandidateGate(
            code: "schema_valid",
            required: true,
            source: "server",
            gateClass: "output_quality",
            evaluationPhase: "post_inference"
        )
        XCTAssertTrue(CandidateAttemptRunner.isOutputQualityGate(gate))
        XCTAssertEqual(CandidateAttemptRunner.effectiveGateClass(for: gate), .outputQuality)
        XCTAssertEqual(CandidateAttemptRunner.effectivePhase(for: gate), .postInference)
    }

    // MARK: - Output quality gate classification falls back to GATE_CLASSIFICATION

    func testOutputQualityGateFallsBackToClassification() {
        let gate = CandidateGate(code: "schema_valid", required: true, source: "server")
        XCTAssertTrue(CandidateAttemptRunner.isOutputQualityGate(gate))
        XCTAssertEqual(CandidateAttemptRunner.effectiveGateClass(for: gate), .outputQuality)
        XCTAssertEqual(CandidateAttemptRunner.effectivePhase(for: gate), .postInference)
    }

    // MARK: - FallbackTrigger serializes new fields correctly

    func testFallbackTriggerNewFieldsSerialize() throws {
        let trigger = FallbackTrigger(
            code: "output_quality_gate_failed",
            stage: "output_quality",
            message: "schema_valid failed",
            gateCode: "schema_valid",
            gateClass: "output_quality",
            evaluationPhase: "post_inference",
            candidateIndex: 0,
            outputVisibleBeforeFailure: false
        )

        let data = try JSONEncoder().encode(trigger)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["gate_code"] as? String, "schema_valid")
        XCTAssertEqual(json["gate_class"] as? String, "output_quality")
        XCTAssertEqual(json["evaluation_phase"] as? String, "post_inference")
        XCTAssertEqual(json["candidate_index"] as? Int, 0)
        XCTAssertEqual(json["output_visible_before_failure"] as? Bool, false)
    }

    // MARK: - GateResult serializes gateClass and evaluationPhase

    func testGateResultNewFieldsSerialize() throws {
        let result = GateResult(
            code: "schema_valid",
            status: .passed,
            gateClass: "output_quality",
            evaluationPhase: "post_inference"
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["gate_class"] as? String, "output_quality")
        XCTAssertEqual(json["evaluation_phase"] as? String, "post_inference")
    }
}

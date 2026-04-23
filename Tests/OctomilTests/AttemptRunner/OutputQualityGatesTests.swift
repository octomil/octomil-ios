import Foundation
import XCTest

@testable import Octomil

// MARK: - Test Doubles

/// Output quality evaluator that can be configured to pass or fail specific gate codes.
private final class StubOutputQualityEvaluator: OutputQualityGateEvaluator, @unchecked Sendable {
    let name: String = "test_evaluator"

    /// Gate codes mapped to their evaluation result.
    let results: [String: GateEvaluationResult]

    init(results: [String: GateEvaluationResult] = [:]) {
        self.results = results
    }

    func evaluate(gate: CandidateGate, response: Any) async -> GateEvaluationResult {
        return results[gate.code] ?? GateEvaluationResult(passed: true, score: 1.0)
    }
}

/// Gate evaluator that always passes (for pre-inference gates).
private struct PassingGateEvaluator: AttemptGateEvaluator {
    func evaluate(gate: CandidateGate, engine: String?, locality: String) -> GateResult {
        GateResult(code: gate.code, status: .passed)
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

final class OutputQualityGatesTests: XCTestCase {

    // MARK: - classifyGate tests

    func testClassifyGateReturnsCorrectValuesForAllReadinessGates() {
        let readinessGates: [(String, Bool)] = [
            ("artifact_verified", true),
            ("runtime_available", true),
            ("model_loads", true),
            ("context_fits", true),
            ("modality_supported", true),
            ("tool_support", true),
        ]

        for (code, expectedBlocking) in readinessGates {
            let c = classifyGate(code)
            XCTAssertEqual(c.gateClass, .readiness, "Gate \(code) should be readiness class")
            XCTAssertEqual(c.evaluationPhase, .preInference, "Gate \(code) should be pre_inference")
            XCTAssertEqual(c.blockingDefault, expectedBlocking, "Gate \(code) blockingDefault mismatch")
        }
    }

    func testClassifyGateReturnsCorrectValuesForPerformanceGates() {
        // min_tokens_per_second: performance, pre_inference, false
        let tps = classifyGate("min_tokens_per_second")
        XCTAssertEqual(tps.gateClass, .performance)
        XCTAssertEqual(tps.evaluationPhase, .preInference)
        XCTAssertEqual(tps.blockingDefault, false)

        // max_ttft_ms: performance, during_inference, false
        let ttft = classifyGate("max_ttft_ms")
        XCTAssertEqual(ttft.gateClass, .performance)
        XCTAssertEqual(ttft.evaluationPhase, .duringInference)
        XCTAssertEqual(ttft.blockingDefault, false)

        // max_error_rate: performance, pre_inference, false
        let err = classifyGate("max_error_rate")
        XCTAssertEqual(err.gateClass, .performance)
        XCTAssertEqual(err.evaluationPhase, .preInference)
        XCTAssertEqual(err.blockingDefault, false)

        // min_free_memory_bytes: performance, pre_inference, true
        let mem = classifyGate("min_free_memory_bytes")
        XCTAssertEqual(mem.gateClass, .performance)
        XCTAssertEqual(mem.evaluationPhase, .preInference)
        XCTAssertEqual(mem.blockingDefault, true)

        // min_free_storage_bytes: performance, pre_inference, true
        let sto = classifyGate("min_free_storage_bytes")
        XCTAssertEqual(sto.gateClass, .performance)
        XCTAssertEqual(sto.evaluationPhase, .preInference)
        XCTAssertEqual(sto.blockingDefault, true)

        // benchmark_fresh: performance, pre_inference, false
        let bm = classifyGate("benchmark_fresh")
        XCTAssertEqual(bm.gateClass, .performance)
        XCTAssertEqual(bm.evaluationPhase, .preInference)
        XCTAssertEqual(bm.blockingDefault, false)
    }

    func testClassifyGateReturnsCorrectValuesForOutputQualityGates() {
        let outputQualityGates: [(String, Bool)] = [
            ("schema_valid", true),
            ("tool_call_valid", true),
            ("safety_passed", true),
            ("evaluator_score_min", false),
            ("json_parseable", true),
            ("max_refusal_rate", false),
        ]

        for (code, expectedBlocking) in outputQualityGates {
            let c = classifyGate(code)
            XCTAssertEqual(c.gateClass, .outputQuality, "Gate \(code) should be output_quality class")
            XCTAssertEqual(c.evaluationPhase, .postInference, "Gate \(code) should be post_inference")
            XCTAssertEqual(c.blockingDefault, expectedBlocking, "Gate \(code) blockingDefault mismatch")
        }
    }

    func testClassifyGateAll18CodesAreMapped() {
        // Every GateCode case should have an entry in GATE_CLASSIFICATION
        for gateCode in GateCode.allCases {
            let classification = GATE_CLASSIFICATION[gateCode.rawValue]
            XCTAssertNotNil(classification, "GateCode.\(gateCode) (\(gateCode.rawValue)) must be in GATE_CLASSIFICATION")
        }
        XCTAssertEqual(GateCode.allCases.count, 18, "Should have exactly 18 gate codes")
        XCTAssertEqual(GATE_CLASSIFICATION.count, 18, "GATE_CLASSIFICATION should have exactly 18 entries")
    }

    func testClassifyGateUnknownCodeReturnsReadinessDefault() {
        let c = classifyGate("totally_unknown_gate_code")
        XCTAssertEqual(c.gateClass, .readiness, "Unknown gates should default to readiness")
        XCTAssertEqual(c.evaluationPhase, .preInference, "Unknown gates should default to pre_inference")
        XCTAssertEqual(c.blockingDefault, true, "Unknown gates should default to blocking (fail-closed)")
    }

    // MARK: - Output quality gates skipped during run()

    func testOutputQualityGatesSkippedDuringRun() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
            CandidateGate(code: "schema_valid", required: true, source: "server"),
            CandidateGate(code: "safety_passed", required: true, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded, "Should succeed — output quality gates should be skipped")
        XCTAssertEqual(result.selectedAttempt?.status, .selected)

        // Gate results should include runtime_available, artifact_verified, and min_tokens_per_second
        // but NOT schema_valid or safety_passed (those are post-inference)
        let gateResults = result.selectedAttempt!.gateResults
        let gateCodes = gateResults.map(\.code)
        XCTAssertTrue(gateCodes.contains("runtime_available"))
        XCTAssertTrue(gateCodes.contains("artifact_verified"))
        XCTAssertTrue(gateCodes.contains("min_tokens_per_second"))
        XCTAssertFalse(gateCodes.contains("schema_valid"), "schema_valid should be skipped during run()")
        XCTAssertFalse(gateCodes.contains("safety_passed"), "safety_passed should be skipped during run()")
    }

    func testOutputQualityGateSkippedEvenWhenRequired() {
        // Even required output quality gates should not block selection during run()
        let runner = CandidateAttemptRunner(fallbackAllowed: false)

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded, "Required output quality gate should be skipped during run()")
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
    }

    // MARK: - Gate results include gateClass and evaluationPhase

    func testGateResultsIncludeClassAndPhase() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
            CandidateGate(code: "min_free_memory_bytes", required: true, thresholdNumber: 500_000_000, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]
        let result = runner.run(candidates: candidates)

        XCTAssertTrue(result.succeeded)

        let gateResults = result.selectedAttempt!.gateResults

        // Check runtime_available gate result
        let rtGate = gateResults.first { $0.code == "runtime_available" }
        XCTAssertNotNil(rtGate)
        XCTAssertEqual(rtGate?.gateClass, "readiness")
        XCTAssertEqual(rtGate?.evaluationPhase, "pre_inference")

        // Check min_tokens_per_second gate result
        let tpsGate = gateResults.first { $0.code == "min_tokens_per_second" }
        XCTAssertNotNil(tpsGate)
        XCTAssertEqual(tpsGate?.gateClass, "performance")
        XCTAssertEqual(tpsGate?.evaluationPhase, "pre_inference")

        // Check min_free_memory_bytes gate result
        let memGate = gateResults.first { $0.code == "min_free_memory_bytes" }
        XCTAssertNotNil(memGate)
        XCTAssertEqual(memGate?.gateClass, "performance")
        XCTAssertEqual(memGate?.evaluationPhase, "pre_inference")
    }

    // MARK: - Quality gate failure before output triggers fallback

    func testQualityGateFailureBeforeOutputTriggersFallback() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "schema_valid": GateEvaluationResult(passed: false, score: 0.0, reasonCode: "invalid_schema"),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        // First candidate should fail at output_quality stage
        XCTAssertEqual(result.attempts.count, 2)
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .outputQuality)
        XCTAssertEqual(result.attempts[0].reason.code, "output_quality_gate_failed")

        // Should have fallen back to cloud
        XCTAssertTrue(result.fallbackUsed)
        XCTAssertNotNil(result.fallbackTrigger)
        XCTAssertEqual(result.fallbackTrigger?.code, "output_quality_gate_failed")
        XCTAssertEqual(result.fallbackTrigger?.gateCode, "schema_valid")
        XCTAssertEqual(result.fallbackTrigger?.gateClass, "output_quality")
        XCTAssertEqual(result.fallbackTrigger?.evaluationPhase, "post_inference")
        XCTAssertEqual(result.fallbackTrigger?.outputVisibleBeforeFailure, false)
    }

    // MARK: - Quality gate failure after first token does NOT fallback

    func testQualityGateFailureAfterFirstTokenDoesNotFallback() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "schema_valid": GateEvaluationResult(passed: false, score: 0.0, reasonCode: "invalid_schema"),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { true }  // Output already visible
        ) { _, _ in
            return "inference result"
        }

        // Should still be selected because output was already visible
        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertEqual(result.attempts.count, 1)

        // The schema_valid gate result should show failed in the results
        let schemaGate = result.selectedAttempt?.gateResults.first { $0.code == "schema_valid" }
        XCTAssertNotNil(schemaGate)
        XCTAssertEqual(schemaGate?.status, .failed)
        XCTAssertEqual(schemaGate?.reasonCode, "invalid_schema")

        // No fallback should have occurred
        XCTAssertFalse(result.fallbackUsed)
    }

    // MARK: - Advisory quality gate failure does not disqualify

    func testAdvisoryQualityGateFailureDoesNotDisqualify() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "evaluator_score_min": GateEvaluationResult(passed: false, score: 0.3, reasonCode: "low_quality"),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "evaluator_score_min", required: false, thresholdNumber: 0.8, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        // Should succeed — advisory (non-required) gate failure does not block
        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertEqual(result.value, "inference result")
        XCTAssertFalse(result.fallbackUsed)

        // The advisory gate should show failed in results
        let scoreGate = result.selectedAttempt?.gateResults.first { $0.code == "evaluator_score_min" }
        XCTAssertNotNil(scoreGate)
        XCTAssertEqual(scoreGate?.status, .failed)
        XCTAssertEqual(scoreGate?.gateClass, "output_quality")
        XCTAssertEqual(scoreGate?.evaluationPhase, "post_inference")
    }

    // MARK: - Required gate with no evaluator fails closed

    func testRequiredGateWithNoEvaluatorFailsClosed() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        // No outputQualityEvaluator provided

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: nil,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        // First candidate should fail because no evaluator is configured
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .outputQuality)
        XCTAssertEqual(result.attempts[0].reason.code, "output_quality_gate_failed")
        XCTAssertTrue(result.attempts[0].reason.message.contains("evaluator"))

        // Check that the gate result shows evaluator_missing
        let schemaGate = result.attempts[0].gateResults.first { $0.code == "schema_valid" }
        XCTAssertNotNil(schemaGate)
        XCTAssertEqual(schemaGate?.status, .failed)
        XCTAssertEqual(schemaGate?.reasonCode, "evaluator_missing")
    }

    func testOptionalGateWithNoEvaluatorProceedsNormally() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        // No outputQualityEvaluator provided

        let gates: [CandidateGate] = [
            CandidateGate(code: "evaluator_score_min", required: false, thresholdNumber: 0.8, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: nil,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        // Should succeed — only optional output quality gates, no evaluator
        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertEqual(result.value, "inference result")
    }

    // MARK: - Private policy prevents fallback on quality gate failure

    func testPrivatePolicyPreventsFallbackOnQualityGateFailure() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: false)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "schema_valid": GateEvaluationResult(passed: false, score: 0.0, reasonCode: "invalid_schema"),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        // Should fail — no fallback allowed
        XCTAssertNil(result.selectedAttempt)
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .outputQuality)
        XCTAssertFalse(result.fallbackUsed)
    }

    // MARK: - Private policy prevents fallback when evaluator missing

    func testPrivatePolicyPreventsFallbackWhenEvaluatorMissing() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: false)

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: nil,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        // Should fail — no fallback, no evaluator
        XCTAssertNil(result.selectedAttempt)
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertEqual(result.attempts[0].status, .failed)
        XCTAssertEqual(result.attempts[0].stage, .outputQuality)
        XCTAssertFalse(result.fallbackUsed)
    }

    // MARK: - All quality gates pass

    func testAllQualityGatesPassSucceeds() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "schema_valid": GateEvaluationResult(passed: true, score: 1.0),
            "safety_passed": GateEvaluationResult(passed: true, score: 1.0),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "schema_valid", required: true, source: "server"),
            CandidateGate(code: "safety_passed", required: true, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "inference result"
        }

        XCTAssertNotNil(result.selectedAttempt)
        XCTAssertEqual(result.selectedAttempt?.status, .selected)
        XCTAssertEqual(result.value, "inference result")
        XCTAssertFalse(result.fallbackUsed)

        // Both quality gates should be in results
        let gateResults = result.selectedAttempt!.gateResults
        let schemaGate = gateResults.first { $0.code == "schema_valid" }
        let safetyGate = gateResults.first { $0.code == "safety_passed" }
        XCTAssertNotNil(schemaGate)
        XCTAssertNotNil(safetyGate)
        XCTAssertEqual(schemaGate?.status, .passed)
        XCTAssertEqual(safetyGate?.status, .passed)
        XCTAssertEqual(schemaGate?.gateClass, "output_quality")
        XCTAssertEqual(schemaGate?.evaluationPhase, "post_inference")
    }

    // MARK: - Output quality gate results enriched with class and phase

    func testOutputQualityGateResultsEnriched() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "json_parseable": GateEvaluationResult(passed: true, score: 1.0),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "json_parseable", required: true, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "{}"
        }

        XCTAssertNotNil(result.selectedAttempt)
        let jsonGate = result.selectedAttempt!.gateResults.first { $0.code == "json_parseable" }
        XCTAssertNotNil(jsonGate)
        XCTAssertEqual(jsonGate?.gateClass, "output_quality")
        XCTAssertEqual(jsonGate?.evaluationPhase, "post_inference")
        XCTAssertEqual(jsonGate?.status, .passed)
    }

    // MARK: - Fallback trigger metadata is populated correctly

    func testFallbackTriggerMetadataOnQualityGateFailure() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "tool_call_valid": GateEvaluationResult(passed: false, score: 0.0, reasonCode: "invalid_args"),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "tool_call_valid", required: true, source: "server"),
        ]

        let candidates = [
            makeLocalCandidate(gates: gates),
            makeCloudCandidate(),
        ]

        let result = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "result"
        }

        XCTAssertTrue(result.fallbackUsed)
        let trigger = result.fallbackTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.code, "output_quality_gate_failed")
        XCTAssertEqual(trigger?.stage, "output_quality")
        XCTAssertEqual(trigger?.gateCode, "tool_call_valid")
        XCTAssertEqual(trigger?.gateClass, "output_quality")
        XCTAssertEqual(trigger?.evaluationPhase, "post_inference")
        XCTAssertEqual(trigger?.candidateIndex, 0)
        XCTAssertEqual(trigger?.outputVisibleBeforeFailure, false)
    }

    // MARK: - RouteEvent quality fields

    func testRouteEventQualityFieldsEncode() throws {
        let event = RouteEvent(
            requestId: "req_123",
            capability: "chat",
            selectedLocality: "local",
            finalMode: "sdk_runtime",
            qualityEvaluatorName: "test_eval",
            qualityScore: 0.95,
            qualityReasonCode: "high_quality",
            advisoryFailures: [["code": "evaluator_score_min", "reason_code": "low_score"]],
            gateFailureCount: 1,
            outputVisibleBeforeFailure: false
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["quality_evaluator_name"] as? String, "test_eval")
        XCTAssertEqual(json["quality_score"] as? Double, 0.95)
        XCTAssertEqual(json["quality_reason_code"] as? String, "high_quality")
        XCTAssertEqual(json["gate_failure_count"] as? Int, 1)
        XCTAssertEqual(json["output_visible_before_failure"] as? Bool, false)

        let advisory = try XCTUnwrap(json["advisory_failures"] as? [[String: String]])
        XCTAssertEqual(advisory.count, 1)
        XCTAssertEqual(advisory[0]["code"], "evaluator_score_min")
    }

    func testRouteEventQualityFieldsOmittedWhenNil() throws {
        let event = RouteEvent(
            requestId: "req_456",
            capability: "chat",
            selectedLocality: "local",
            finalMode: "sdk_runtime"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["quality_evaluator_name"])
        XCTAssertNil(json["quality_score"])
        XCTAssertNil(json["quality_reason_code"])
        XCTAssertNil(json["advisory_failures"])
        XCTAssertNil(json["gate_failure_count"])
        XCTAssertNil(json["output_visible_before_failure"])
    }

    func testRouteEventDecodesQualityFields() throws {
        let jsonString = """
        {
            "route_id": "route_abc",
            "request_id": "req_789",
            "capability": "chat",
            "selected_locality": "local",
            "final_locality": "local",
            "final_mode": "sdk_runtime",
            "fallback_used": false,
            "candidate_attempts": 1,
            "quality_evaluator_name": "my_eval",
            "quality_score": 0.75,
            "quality_reason_code": "ok",
            "gate_failure_count": 2,
            "output_visible_before_failure": true,
            "advisory_failures": [{"code": "evaluator_score_min", "reason_code": "low"}]
        }
        """
        let data = jsonString.data(using: .utf8)!
        let event = try JSONDecoder().decode(RouteEvent.self, from: data)

        XCTAssertEqual(event.qualityEvaluatorName, "my_eval")
        XCTAssertEqual(event.qualityScore, 0.75)
        XCTAssertEqual(event.qualityReasonCode, "ok")
        XCTAssertEqual(event.gateFailureCount, 2)
        XCTAssertEqual(event.outputVisibleBeforeFailure, true)
        XCTAssertEqual(event.advisoryFailures?.count, 1)
        XCTAssertEqual(event.advisoryFailures?[0]["code"], "evaluator_score_min")
    }

    // MARK: - Mixed pre-inference and post-inference gates

    func testMixedGatesEvaluatedCorrectly() async {
        let runner = CandidateAttemptRunner(fallbackAllowed: true)
        let oqEvaluator = StubOutputQualityEvaluator(results: [
            "schema_valid": GateEvaluationResult(passed: true, score: 1.0),
        ])

        let gates: [CandidateGate] = [
            CandidateGate(code: "min_tokens_per_second", required: true, thresholdNumber: 10.0, source: "server"),
            CandidateGate(code: "schema_valid", required: true, source: "server"),
        ]

        let candidates = [makeLocalCandidate(gates: gates)]

        // First verify run() skips output quality gates
        let runResult = runner.run(candidates: candidates)
        XCTAssertTrue(runResult.succeeded)
        let runGateCodes = runResult.selectedAttempt!.gateResults.map(\.code)
        XCTAssertTrue(runGateCodes.contains("min_tokens_per_second"))
        XCTAssertFalse(runGateCodes.contains("schema_valid"))

        // Then verify runWithInference evaluates both
        let inferResult = await runner.runWithInference(
            candidates: candidates,
            outputQualityEvaluator: oqEvaluator,
            firstOutputEmitted: { false }
        ) { _, _ in
            return "result"
        }

        XCTAssertNotNil(inferResult.selectedAttempt)
        let inferGateCodes = inferResult.selectedAttempt!.gateResults.map(\.code)
        XCTAssertTrue(inferGateCodes.contains("min_tokens_per_second"))
        XCTAssertTrue(inferGateCodes.contains("schema_valid"))
    }

    // MARK: - GateCode enum covers all 18 codes

    func testGateCodeEnumCoversAll18Codes() {
        let expected: Set<String> = [
            // Readiness
            "artifact_verified", "runtime_available", "model_loads",
            "context_fits", "modality_supported", "tool_support",
            // Performance
            "min_tokens_per_second", "max_ttft_ms", "max_error_rate",
            "min_free_memory_bytes", "min_free_storage_bytes", "benchmark_fresh",
            // Output quality
            "schema_valid", "tool_call_valid", "safety_passed",
            "evaluator_score_min", "json_parseable", "max_refusal_rate",
        ]
        let actual = Set(GateCode.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected, "GateCode enum must cover all 18 gate codes")
    }
}

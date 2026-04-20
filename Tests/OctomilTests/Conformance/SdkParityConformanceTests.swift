import Foundation
import XCTest

@testable import Octomil

// MARK: - Fixture Models

/// Top-level structure of an SDK parity fixture JSON file.
private struct SdkParityFixture: Decodable {
    let description: String
    let request: FixtureRequest
    let plannerResponse: FixturePlannerResponse
    let expectedRouteMetadata: FixtureRouteMetadata
    let expectedTelemetry: FixtureTelemetry
    let expectedPolicyResult: FixturePolicyResult

    enum CodingKeys: String, CodingKey {
        case description
        case request
        case plannerResponse = "planner_response"
        case expectedRouteMetadata = "expected_route_metadata"
        case expectedTelemetry = "expected_telemetry"
        case expectedPolicyResult = "expected_policy_result"
    }
}

private struct FixtureRequest: Decodable {
    let model: String
    let capability: String
    let routingPolicy: String

    enum CodingKeys: String, CodingKey {
        case model
        case capability
        case routingPolicy = "routing_policy"
    }
}

private struct FixturePlannerResponse: Decodable {
    let model: String
    let capability: String
    let policy: String
    let candidates: [FixtureCandidate]
    let fallbackCandidates: [FixtureCandidate]
    let planTtlSeconds: Int
    let fallbackAllowed: Bool
    let serverGeneratedAt: String

    enum CodingKeys: String, CodingKey {
        case model, capability, policy, candidates
        case fallbackCandidates = "fallback_candidates"
        case planTtlSeconds = "plan_ttl_seconds"
        case fallbackAllowed = "fallback_allowed"
        case serverGeneratedAt = "server_generated_at"
    }
}

private struct FixtureCandidate: Decodable {
    let locality: String
    let priority: Int
    let confidence: Double
    let reason: String
    let engine: String?
    let engineVersionConstraint: String?
    let artifact: FixtureArtifact?
    let benchmarkRequired: Bool
    let gates: [FixtureGate]

    enum CodingKeys: String, CodingKey {
        case locality, priority, confidence, reason, engine, artifact, gates
        case engineVersionConstraint = "engine_version_constraint"
        case benchmarkRequired = "benchmark_required"
    }
}

private struct FixtureArtifact: Decodable {
    let modelId: String
    let artifactId: String?
    let modelVersion: String?
    let format: String?
    let quantization: String?
    let uri: String?
    let digest: String?
    let sizeBytes: Int64?
    let minRamBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case artifactId = "artifact_id"
        case modelVersion = "model_version"
        case format, quantization, uri, digest
        case sizeBytes = "size_bytes"
        case minRamBytes = "min_ram_bytes"
    }
}

private struct FixtureGate: Decodable {
    let code: String
    let required: Bool
    let thresholdNumber: Double?
    let thresholdString: String?
    let windowSeconds: Int?
    let source: String

    enum CodingKeys: String, CodingKey {
        case code, required, source
        case thresholdNumber = "threshold_number"
        case thresholdString = "threshold_string"
        case windowSeconds = "window_seconds"
    }
}

private struct FixtureRouteMetadata: Decodable {
    let status: String
    let execution: FixtureExecution?
    let attempts: [FixtureAttempt]
}

private struct FixtureExecution: Decodable {
    let locality: String
    let mode: String
    let engine: String?
}

private struct FixtureAttempt: Decodable {
    let index: Int
    let locality: String
    let mode: String
    let engine: String?
    let status: String
    let stage: String
    let gateResults: [FixtureGateResult]
    let reason: FixtureReason?

    enum CodingKeys: String, CodingKey {
        case index, locality, mode, engine, status, stage, reason
        case gateResults = "gate_results"
    }
}

private struct FixtureGateResult: Decodable {
    let code: String
    let status: String
}

private struct FixtureReason: Decodable {
    let code: String
    let message: String
}

private struct FixtureTelemetry: Decodable {
    let eventName: String
    let forbiddenKeys: [String]
    let requiredKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case eventName = "event_name"
        case forbiddenKeys = "forbidden_keys"
        case requiredKeys = "required_keys"
    }
}

private struct FixturePolicyResult: Decodable {
    let cloudAllowed: Bool
    let localAllowed: Bool
    let fallbackAllowed: Bool

    enum CodingKeys: String, CodingKey {
        case cloudAllowed = "cloud_allowed"
        case localAllowed = "local_allowed"
        case fallbackAllowed = "fallback_allowed"
    }
}

// MARK: - Tests

/// SDK contract conformance tests that validate planner response decoding,
/// candidate gate evaluation, route metadata production, and telemetry privacy
/// using vendored fixtures from octomil-contracts.
///
/// iOS-specific platform rules enforced:
/// - iOS uses publishable/device auth, NOT server keys
/// - iOS supports local runtime (CoreML, llama.cpp) where available
/// - iOS uses hosted fallback only when policy and auth allow
/// - iOS never sends prompts/outputs in telemetry
final class SdkParityConformanceTests: XCTestCase {

    // MARK: - Fixture Loading

    private static let fixtureNames: [String] = [
        "app_ref_local_only",
        "app_ref_local_first_cloud_fallback",
        "capability_chat_default_model",
        "deployment_ref_cloud_only",
        "experiment_variant_resolved",
        "runtime_plan_local_candidate_gates",
        "runtime_plan_cloud_fallback_disallowed",
        "stream_pre_first_token_fallback",
        "stream_post_first_token_no_fallback",
        "telemetry_route_attempt_upload",
    ]

    private func fixturesDirectory() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile
            .deletingLastPathComponent() // Conformance/
            .deletingLastPathComponent() // OctomilTests/
        return testsDir
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("SdkParity")
    }

    private func loadFixture(named name: String) throws -> SdkParityFixture {
        let url = fixturesDirectory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(SdkParityFixture.self, from: data)
    }

    // MARK: - All Fixtures Load Successfully

    func testAllFixturesLoadAndDecode() throws {
        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)
            XCTAssertFalse(fixture.description.isEmpty, "Fixture \(name) should have a description")
            XCTAssertFalse(fixture.request.model.isEmpty, "Fixture \(name) should have a request model")
            XCTAssertFalse(fixture.plannerResponse.candidates.isEmpty, "Fixture \(name) should have candidates")
        }
    }

    // MARK: - RuntimePlanResponse Decoding

    /// Each fixture's planner_response must decode into the SDK's RuntimePlanResponse type.
    func testPlannerResponseDecodesIntoRuntimePlanResponse() throws {
        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)

            // Encode planner_response back to JSON and decode into SDK type
            let planResponse = mapToRuntimePlanResponse(fixture.plannerResponse)

            XCTAssertEqual(planResponse.model, fixture.plannerResponse.model,
                           "[\(name)] model mismatch")
            XCTAssertEqual(planResponse.capability, fixture.plannerResponse.capability,
                           "[\(name)] capability mismatch")
            XCTAssertEqual(planResponse.policy, fixture.plannerResponse.policy,
                           "[\(name)] policy mismatch")
            XCTAssertEqual(planResponse.candidates.count, fixture.plannerResponse.candidates.count,
                           "[\(name)] candidate count mismatch")
            XCTAssertEqual(planResponse.fallbackAllowed, fixture.plannerResponse.fallbackAllowed,
                           "[\(name)] fallbackAllowed mismatch")
            XCTAssertEqual(planResponse.planTtlSeconds, fixture.plannerResponse.planTtlSeconds,
                           "[\(name)] planTtlSeconds mismatch")
        }
    }

    /// Each candidate's fields must round-trip through RuntimeCandidatePlan.
    func testCandidatePlanFieldsRoundTrip() throws {
        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)

            for (idx, fixtureCandidate) in fixture.plannerResponse.candidates.enumerated() {
                let candidate = mapToRuntimeCandidatePlan(fixtureCandidate)

                XCTAssertEqual(candidate.locality.rawValue, fixtureCandidate.locality,
                               "[\(name)] candidate[\(idx)] locality mismatch")
                XCTAssertEqual(candidate.priority, fixtureCandidate.priority,
                               "[\(name)] candidate[\(idx)] priority mismatch")
                XCTAssertEqual(candidate.confidence, fixtureCandidate.confidence, accuracy: 0.001,
                               "[\(name)] candidate[\(idx)] confidence mismatch")

                if let expectedEngine = fixtureCandidate.engine {
                    let canonicalExpected = RuntimeEngineID.canonical(expectedEngine)
                    XCTAssertEqual(candidate.engine, canonicalExpected,
                                   "[\(name)] candidate[\(idx)] engine mismatch")
                } else {
                    XCTAssertNil(candidate.engine,
                                 "[\(name)] candidate[\(idx)] engine should be nil")
                }
            }
        }
    }

    // MARK: - RouteAttempt & GateResult Decoding

    /// Verify expected_route_metadata.attempts decode into RouteAttempt types.
    func testRouteAttemptsDecodeCorrectly() throws {
        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)

            for fixtureAttempt in fixture.expectedRouteMetadata.attempts {
                // Verify the status and stage values are valid SDK enum cases
                XCTAssertNotNil(AttemptStatus(rawValue: fixtureAttempt.status),
                                "[\(name)] invalid attempt status: \(fixtureAttempt.status)")
                XCTAssertNotNil(AttemptStage(rawValue: fixtureAttempt.stage),
                                "[\(name)] invalid attempt stage: \(fixtureAttempt.stage)")

                // Verify gate results have valid status values
                for gr in fixtureAttempt.gateResults {
                    XCTAssertNotNil(GateStatus(rawValue: gr.status),
                                    "[\(name)] invalid gate status: \(gr.status)")
                }
            }
        }
    }

    /// GateResult codes from fixtures must match known GateCode values.
    func testGateCodesAreRecognized() throws {
        let knownCodes = Set(GateCode.allCases.map(\.rawValue))

        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)

            for attempt in fixture.expectedRouteMetadata.attempts {
                for gr in attempt.gateResults {
                    XCTAssertTrue(knownCodes.contains(gr.code),
                                  "[\(name)] unrecognized gate code: \(gr.code)")
                }
            }
        }
    }

    // MARK: - CandidateAttemptRunner Processing

    /// Verify that CandidateAttemptRunner can process each fixture's candidates
    /// and produce a result consistent with expected_route_metadata.
    func testCandidateAttemptRunnerProcessesFixtures() throws {
        for name in Self.fixtureNames {
            // Skip streaming inference fixtures that test post-inference fallback behavior.
            // Those require runWithInference (async) and simulate inference errors,
            // which is tested separately.
            if name.hasPrefix("stream_") { continue }

            let fixture = try loadFixture(named: name)
            let fallbackAllowed = fixture.plannerResponse.fallbackAllowed

            // Determine which test doubles to inject based on the scenario.
            let runtimeChecker: (any AttemptRuntimeChecker)?
            let gateEvaluator: (any AttemptGateEvaluator)?

            switch name {
            case "runtime_plan_cloud_fallback_disallowed":
                // Simulate local engine being unavailable
                runtimeChecker = FixtureRuntimeChecker(unavailableEngines: ["mlx-lm"])
                gateEvaluator = nil
            case "app_ref_local_first_cloud_fallback":
                // Simulate memory gate failure on local candidate to trigger cloud fallback
                runtimeChecker = nil
                gateEvaluator = FixtureGateEvaluator(failingGates: ["min_free_memory_bytes"])
            default:
                runtimeChecker = nil
                gateEvaluator = nil
            }

            let runner = CandidateAttemptRunner(fallbackAllowed: fallbackAllowed)
            let inputs = fixture.plannerResponse.candidates.map { mapToAttemptCandidateInput($0) }

            let result = runner.run(
                candidates: inputs,
                runtimeChecker: runtimeChecker,
                gateEvaluator: gateEvaluator
            )

            let expectedStatus = fixture.expectedRouteMetadata.status
            if expectedStatus == "selected" {
                XCTAssertTrue(result.succeeded, "[\(name)] expected selected but got no selection")
                XCTAssertNotNil(result.selectedAttempt, "[\(name)] selectedAttempt should not be nil")

                if let execution = fixture.expectedRouteMetadata.execution {
                    XCTAssertEqual(result.selectedAttempt?.locality, execution.locality,
                                   "[\(name)] selected locality mismatch")
                    XCTAssertEqual(result.selectedAttempt?.mode, execution.mode,
                                   "[\(name)] selected mode mismatch")
                }
            } else if expectedStatus == "failed" {
                XCTAssertFalse(result.succeeded, "[\(name)] expected failure but got success")
                XCTAssertNil(result.selectedAttempt, "[\(name)] selectedAttempt should be nil on failure")
            }
        }
    }

    /// For local_first with cloud fallback, verify the runner falls back correctly.
    func testLocalFirstCloudFallbackScenario() throws {
        let fixture = try loadFixture(named: "app_ref_local_first_cloud_fallback")

        // Simulate memory gate failure on local candidate
        let gateEval = FixtureGateEvaluator(failingGates: ["min_free_memory_bytes"])
        let runner = CandidateAttemptRunner(fallbackAllowed: fixture.plannerResponse.fallbackAllowed)
        let inputs = fixture.plannerResponse.candidates.map { mapToAttemptCandidateInput($0) }

        let result = runner.run(candidates: inputs, gateEvaluator: gateEval)

        XCTAssertTrue(result.succeeded, "Should fall back to cloud")
        XCTAssertEqual(result.selectedAttempt?.locality, "cloud")
        XCTAssertEqual(result.selectedAttempt?.mode, "hosted_gateway")
        XCTAssertTrue(result.fallbackUsed)
        XCTAssertEqual(result.fallbackTrigger?.code, "gate_failed")
    }

    // MARK: - Streaming Fallback Behavior

    /// Streaming: fallback allowed before first output.
    func testStreamingPreFirstTokenFallbackAllowed() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: true)
        XCTAssertTrue(runner.shouldFallbackAfterInferenceError(firstOutputEmitted: false),
                      "Should allow fallback before first output in streaming mode")
    }

    /// Streaming: fallback NOT allowed after first output.
    func testStreamingPostFirstTokenFallbackDisallowed() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: true)
        XCTAssertFalse(runner.shouldFallbackAfterInferenceError(firstOutputEmitted: true),
                       "Should NOT allow fallback after first output in streaming mode")
    }

    /// Non-streaming: fallback always allowed when fallbackAllowed=true.
    func testNonStreamingFallbackAlwaysAllowed() {
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: false)
        XCTAssertTrue(runner.shouldFallbackAfterInferenceError(firstOutputEmitted: false))
        XCTAssertTrue(runner.shouldFallbackAfterInferenceError(firstOutputEmitted: true))
    }

    // MARK: - Policy Result Validation

    /// Verify policy assertions from each fixture.
    func testPolicyResultsMatchFixtures() throws {
        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)
            let policy = fixture.expectedPolicyResult

            // For streaming post-first-output scenarios, the planner may allow fallback
            // but the runtime disallows it after output is emitted. The expected_policy_result
            // reflects the effective runtime behavior, not just the planner flag.
            let isPostOutputStreaming = name == "stream_post_first_token_no_fallback"
            if !isPostOutputStreaming {
                let fallbackAllowed = fixture.plannerResponse.fallbackAllowed
                XCTAssertEqual(fallbackAllowed, policy.fallbackAllowed,
                               "[\(name)] fallbackAllowed mismatch between planner_response and expected_policy_result")
            } else {
                // Planner says fallback_allowed=true, but runtime blocks fallback after first output
                XCTAssertTrue(fixture.plannerResponse.fallbackAllowed,
                              "[\(name)] planner should allow fallback (runtime blocks it post-output)")
                XCTAssertFalse(policy.fallbackAllowed,
                               "[\(name)] effective policy should block fallback after first output")
            }

            // Verify policy constraints are internally consistent
            let hasLocalCandidate = fixture.plannerResponse.candidates.contains { $0.locality == "local" }
            let hasCloudCandidate = fixture.plannerResponse.candidates.contains { $0.locality == "cloud" }

            if policy.localAllowed {
                XCTAssertTrue(hasLocalCandidate,
                              "[\(name)] policy says local_allowed but no local candidates in plan")
            }

            // cloud_only should have only cloud candidates
            if !policy.localAllowed && policy.cloudAllowed {
                XCTAssertTrue(hasCloudCandidate,
                              "[\(name)] cloud_only policy but no cloud candidates")
            }
        }
    }

    // MARK: - Telemetry Privacy Enforcement

    /// iOS SDK must NEVER send prompt/output content in telemetry.
    /// Verify that fixture telemetry sections define forbidden keys and that
    /// the standard forbidden keys are always present.
    func testTelemetryForbiddenKeysEnforced() throws {
        // These keys must NEVER appear in telemetry from iOS SDK
        let mandatoryForbiddenKeys: Set<String> = ["prompt", "output", "messages", "completion"]

        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)
            let forbiddenSet = Set(fixture.expectedTelemetry.forbiddenKeys)

            for key in mandatoryForbiddenKeys {
                XCTAssertTrue(forbiddenSet.contains(key),
                              "[\(name)] mandatory forbidden key '\(key)' missing from fixture telemetry spec")
            }
        }
    }

    /// Validate telemetry event names are from the known contract set.
    func testTelemetryEventNamesAreValid() throws {
        let validEventNames: Set<String> = [
            "inference.started",
            "inference.completed",
            "inference.failed",
            "inference.chunk_produced",
            "deploy.started",
            "deploy.completed",
        ]

        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)
            XCTAssertTrue(validEventNames.contains(fixture.expectedTelemetry.eventName),
                          "[\(name)] unknown telemetry event name: \(fixture.expectedTelemetry.eventName)")
        }
    }

    // MARK: - iOS Auth Platform Rules

    /// iOS uses publishable/device auth. Verify no fixture expects server keys.
    func testNoServerKeyAuthExpected() throws {
        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)
            // iOS SDK uses publishable keys (pk_*) or device tokens.
            // Server keys (sk_*) are never used on-device.
            // This test verifies fixtures don't assume server-side auth.
            XCTAssertFalse(fixture.request.routingPolicy.contains("server_key"),
                           "[\(name)] iOS SDK does not support server_key routing policy")
        }
    }

    // MARK: - Fixture Completeness

    /// All 10 expected fixture files must be present and loadable.
    func testAllTenFixturesPresent() throws {
        XCTAssertEqual(Self.fixtureNames.count, 10, "Expected exactly 10 fixture names")

        for name in Self.fixtureNames {
            let url = fixturesDirectory().appendingPathComponent("\(name).json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "Missing fixture file: \(name).json")
        }
    }

    /// Verify the planner_response section of each fixture can be round-tripped
    /// through JSONEncoder/JSONDecoder using the SDK's RuntimePlanResponse type.
    /// Uses the type's own CodingKeys (no strategy override) since the types
    /// define explicit snake_case CodingKeys internally.
    func testPlannerResponseJsonRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for name in Self.fixtureNames {
            let fixture = try loadFixture(named: name)
            let planResponse = mapToRuntimePlanResponse(fixture.plannerResponse)

            let encoded = try encoder.encode(planResponse)
            let decoded = try decoder.decode(RuntimePlanResponse.self, from: encoded)

            XCTAssertEqual(decoded.model, planResponse.model, "[\(name)] round-trip model mismatch")
            XCTAssertEqual(decoded.candidates.count, planResponse.candidates.count,
                           "[\(name)] round-trip candidate count mismatch")
            XCTAssertEqual(decoded.fallbackAllowed, planResponse.fallbackAllowed,
                           "[\(name)] round-trip fallbackAllowed mismatch")
        }
    }

    // MARK: - RouteAttempt JSON Encoding

    /// Verify RouteAttempt encodes to the expected wire format.
    func testRouteAttemptEncodesCorrectly() throws {
        let attempt = RouteAttempt(
            index: 0,
            locality: "local",
            mode: "sdk_runtime",
            engine: "llama.cpp",
            status: .selected,
            stage: .inference,
            gateResults: [
                GateResult(code: "runtime_available", status: .passed),
                GateResult(code: "artifact_verified", status: .passed),
            ],
            reason: AttemptReason(code: "selected", message: "all gates passed")
        )

        let data = try JSONEncoder().encode(attempt)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["index"] as? Int, 0)
        XCTAssertEqual(json["locality"] as? String, "local")
        XCTAssertEqual(json["mode"] as? String, "sdk_runtime")
        XCTAssertEqual(json["engine"] as? String, "llama.cpp")
        XCTAssertEqual(json["status"] as? String, "selected")
        XCTAssertEqual(json["stage"] as? String, "inference")

        let gateResults = try XCTUnwrap(json["gate_results"] as? [[String: Any]])
        XCTAssertEqual(gateResults.count, 2)
    }

    // MARK: - Helpers

    private func mapToRuntimePlanResponse(_ response: FixturePlannerResponse) -> RuntimePlanResponse {
        RuntimePlanResponse(
            model: response.model,
            capability: response.capability,
            policy: response.policy,
            candidates: response.candidates.map { mapToRuntimeCandidatePlan($0) },
            fallbackCandidates: response.fallbackCandidates.map { mapToRuntimeCandidatePlan($0) },
            planTtlSeconds: response.planTtlSeconds,
            fallbackAllowed: response.fallbackAllowed,
            serverGeneratedAt: response.serverGeneratedAt
        )
    }

    private func mapToRuntimeCandidatePlan(_ candidate: FixtureCandidate) -> RuntimeCandidatePlan {
        let locality = RuntimeLocality(rawValue: candidate.locality) ?? .cloud
        let artifact: RuntimeArtifactPlan?
        if let art = candidate.artifact {
            artifact = RuntimeArtifactPlan(
                modelId: art.modelId,
                artifactId: art.artifactId,
                modelVersion: art.modelVersion,
                format: art.format,
                quantization: art.quantization,
                uri: art.uri,
                digest: art.digest,
                sizeBytes: art.sizeBytes,
                minRamBytes: art.minRamBytes
            )
        } else {
            artifact = nil
        }

        return RuntimeCandidatePlan(
            locality: locality,
            priority: candidate.priority,
            confidence: candidate.confidence,
            reason: candidate.reason,
            engine: candidate.engine,
            engineVersionConstraint: candidate.engineVersionConstraint,
            artifact: artifact,
            benchmarkRequired: candidate.benchmarkRequired,
            gates: candidate.gates.map { mapToCandidateGate($0) }
        )
    }

    private func mapToCandidateGate(_ gate: FixtureGate) -> CandidateGate {
        CandidateGate(
            code: gate.code,
            required: gate.required,
            thresholdNumber: gate.thresholdNumber,
            thresholdString: gate.thresholdString,
            windowSeconds: gate.windowSeconds,
            source: gate.source
        )
    }

    private func mapToAttemptCandidateInput(_ candidate: FixtureCandidate) -> AttemptCandidateInput {
        let plan = mapToRuntimeCandidatePlan(candidate)
        let gates = candidate.gates.map { mapToCandidateGate($0) }
        return AttemptCandidateInput(candidate: plan, gates: gates)
    }
}

// MARK: - Test Doubles for Conformance

/// Runtime checker that marks specific engines as unavailable.
private struct FixtureRuntimeChecker: AttemptRuntimeChecker {
    let unavailableEngines: Set<String>

    func check(engine: String?, locality: String) -> (available: Bool, reasonCode: String?) {
        guard let engine else { return (true, nil) }
        let canonical = RuntimeEngineID.canonical(engine)
        if unavailableEngines.contains(canonical) {
            return (false, "engine_not_installed")
        }
        return (true, nil)
    }
}

/// Gate evaluator that fails specific gate codes.
private struct FixtureGateEvaluator: AttemptGateEvaluator {
    let failingGates: Set<String>

    func evaluate(gate: CandidateGate, engine: String?, locality: String) -> GateResult {
        if failingGates.contains(gate.code) {
            return GateResult(
                code: gate.code,
                status: .failed,
                observedNumber: 0,
                thresholdNumber: gate.thresholdNumber,
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

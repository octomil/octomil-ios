import XCTest
@testable import Octomil

// MARK: - Production Routing Integration Tests

/// Tests for the production request-path routing and telemetry integration.
///
/// These tests verify that:
/// 1. Public request paths carry RouteMetadata on every Response
/// 2. First-token streaming lockout prevents fallback after first output
/// 3. Deployment/experiment refs route correctly through ParsedModelRef
/// 4. Telemetry route events match the canonical contract shape (no content leaks)
final class ProductionRoutingTests: XCTestCase {

    // MARK: - 1. Route metadata on public responses

    func testCreateResponseCarriesRouteMetadata() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "routed response"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "phi-4-mini", input: [.text("Hello")])
        )

        // Response must include route metadata
        XCTAssertNotNil(response.routeMetadata, "Response must carry routeMetadata")

        let meta = response.routeMetadata!
        XCTAssertFalse(meta.routeId.isEmpty, "routeId must be non-empty")
        XCTAssertEqual(meta.modelRefKind, "plain_id")
        XCTAssertFalse(meta.finalLocality.isEmpty)
        XCTAssertGreaterThanOrEqual(meta.candidateAttempts, 0)
    }

    func testStreamResponseCarriesRouteMetadata() async throws {
        let runtime = RoutingStreamMockRuntime(chunks: [
            RuntimeChunk(text: "streamed"),
            RuntimeChunk(text: " response"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        var doneResponse: Response?
        for try await event in responses.stream(
            ResponseRequest(model: "phi-4-mini", input: [.text("Hello")])
        ) {
            if case .done(let resp) = event {
                doneResponse = resp
            }
        }

        XCTAssertNotNil(doneResponse, "Stream must emit a .done event")
        XCTAssertNotNil(doneResponse?.routeMetadata, "Streaming response must carry routeMetadata")

        let meta = doneResponse!.routeMetadata!
        XCTAssertFalse(meta.routeId.isEmpty)
        XCTAssertEqual(meta.modelRefKind, "plain_id")
    }

    func testRouteMetadataContainsPlannerSource() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "ok"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "test-model", input: [.text("Hi")])
        )

        let meta = response.routeMetadata!
        // Without a cached plan, planner source should be "none" (direct routing)
        XCTAssertEqual(meta.plannerSource, "none")
    }

    // MARK: - 2. First-token streaming lockout

    func testStreamingFallbackAllowedBeforeFirstToken() async throws {
        // The CandidateAttemptRunner should allow fallback before any output is emitted.
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: true)
        XCTAssertTrue(
            runner.shouldFallbackAfterInferenceError(firstOutputEmitted: false),
            "Fallback must be allowed before first token in streaming mode"
        )
    }

    func testStreamingFallbackBlockedAfterFirstToken() async throws {
        // After the first output token is emitted, fallback must be forbidden.
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: true)
        XCTAssertFalse(
            runner.shouldFallbackAfterInferenceError(firstOutputEmitted: true),
            "Fallback must be blocked after first token is emitted in streaming mode"
        )
    }

    func testNonStreamingFallbackAlwaysAllowed() async throws {
        // Non-streaming requests should always allow fallback regardless of output state.
        let runner = CandidateAttemptRunner(fallbackAllowed: true, streaming: false)
        XCTAssertTrue(
            runner.shouldFallbackAfterInferenceError(firstOutputEmitted: false),
            "Non-streaming fallback must be allowed"
        )
        XCTAssertTrue(
            runner.shouldFallbackAfterInferenceError(firstOutputEmitted: true),
            "Non-streaming fallback must be allowed even after output"
        )
    }

    func testStreamingFirstTokenLockoutInAttemptRunner() async throws {
        // runWithInference should record "inference_error_after_first_output" when
        // the first token has already been emitted.
        let failingCandidate = AttemptCandidateInput(candidate: RuntimeCandidatePlan(
            locality: .local,
            priority: 0,
            confidence: 1.0,
            reason: "test local",
            engine: "coreml"
        ))
        let cloudFallback = AttemptCandidateInput(candidate: RuntimeCandidatePlan(
            locality: .cloud,
            priority: 1,
            confidence: 0.8,
            reason: "test cloud fallback",
            engine: "cloud"
        ))

        var firstOutputEmitted = false

        let result = await CandidateAttemptRunner(
            fallbackAllowed: true,
            streaming: true
        ).runWithInference(
            candidates: [failingCandidate, cloudFallback],
            firstOutputEmitted: { firstOutputEmitted }
        ) { candidate, _ in
            if candidate.candidate.locality == .local {
                // Simulate: first token was emitted, then error
                firstOutputEmitted = true
                throw TestRoutingError.inferenceFailedAfterFirstToken
            }
            return RuntimeResponse(text: "cloud result")
        }

        // After first token lockout, the runner should NOT fall back to cloud
        XCTAssertNil(result.value, "Should not produce a value when locked out after first token")

        // The first attempt should record the right error code
        let localAttempt = result.attempts.first { $0.locality == "local" && $0.status == .failed }
        XCTAssertNotNil(localAttempt)
        XCTAssertEqual(localAttempt?.reason.code, "inference_error_after_first_output")
    }

    // MARK: - 3. Deployment/experiment refs route correctly

    func testDeploymentRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("dep_abc123")
        XCTAssertEqual(ref.kind, .deploymentRef)
        XCTAssertEqual(ref.raw, "dep_abc123")
    }

    func testExperimentRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("exp_variant_42")
        XCTAssertEqual(ref.kind, .experimentRef)
        XCTAssertEqual(ref.raw, "exp_variant_42")
    }

    func testAppRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("@app/myapp/chat")
        XCTAssertEqual(ref.kind, .appRef)
        XCTAssertEqual(ref.raw, "@app/myapp/chat")
    }

    func testCapabilityRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("@capability/chat")
        XCTAssertEqual(ref.kind, .capabilityRef)
        XCTAssertEqual(ref.raw, "@capability/chat")
    }

    func testPlainIdParsedCorrectly() {
        let ref = ParsedModelRef.parse("phi-4-mini")
        XCTAssertEqual(ref.kind, .plainId)
        XCTAssertEqual(ref.raw, "phi-4-mini")
    }

    func testDeploymentRefCarriedInRouteMetadata() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "deployed"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "dep_deployment_123", input: [.text("Hi")])
        )

        XCTAssertEqual(
            response.routeMetadata?.modelRefKind, "deployment_ref",
            "Route metadata must reflect the deployment ref kind"
        )
    }

    func testExperimentRefCarriedInRouteMetadata() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "experiment"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "exp_variant_42", input: [.text("Hi")])
        )

        XCTAssertEqual(
            response.routeMetadata?.modelRefKind, "experiment_ref",
            "Route metadata must reflect the experiment ref kind"
        )
    }

    func testAppRefCarriedInRouteMetadata() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "app result"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "@app/myapp/chat", input: [.text("Hi")])
        )

        XCTAssertEqual(
            response.routeMetadata?.modelRefKind, "app_ref",
            "Route metadata must reflect the app ref kind"
        )
    }

    func testDeploymentRefRoutesViaRequestRouter() {
        let router = RequestRouter()
        let context = RequestRoutingContext(
            model: "dep_deploy_456",
            capability: "chat",
            streaming: false
        )
        let decision = router.resolve(context: context)

        // Without a plan, should fall back to hosted gateway
        XCTAssertEqual(decision.routeMetadata.modelRefKind, "deployment_ref")
        XCTAssertEqual(decision.locality, "cloud")
        XCTAssertEqual(decision.mode, "hosted_gateway")
    }

    func testExperimentRefRoutesViaRequestRouter() {
        let router = RequestRouter()
        let context = RequestRoutingContext(
            model: "exp_variant_99",
            capability: "chat",
            streaming: false
        )
        let decision = router.resolve(context: context)

        XCTAssertEqual(decision.routeMetadata.modelRefKind, "experiment_ref")
    }

    // MARK: - 4. Telemetry event matches contract shape

    func testRouteEventFromDecisionHasCanonicalFields() {
        let metadata = RouteMetadata(
            routeId: "route_abc",
            planId: "plan_123",
            plannerSource: "cache",
            policy: "local_first",
            finalLocality: "local",
            engine: "coreml",
            modelRefKind: "deployment_ref",
            fallbackUsed: true,
            fallbackTriggerCode: "gate_failed",
            candidateAttempts: 3
        )

        let decision = RoutingDecisionResult(
            locality: "local",
            mode: "sdk_runtime",
            engine: "coreml",
            routeMetadata: metadata,
            attemptResult: AttemptLoopResult()
        )

        let routeEvent = RouteEvent.from(
            decision: decision,
            requestId: "req_xyz",
            capability: "chat"
        )

        // Verify all canonical fields
        XCTAssertEqual(routeEvent.routeId, "route_abc")
        XCTAssertEqual(routeEvent.requestId, "req_xyz")
        XCTAssertEqual(routeEvent.planId, "plan_123")
        XCTAssertEqual(routeEvent.capability, "chat")
        XCTAssertEqual(routeEvent.policy, "local_first")
        XCTAssertEqual(routeEvent.plannerSource, "cache")
        XCTAssertEqual(routeEvent.finalLocality, "local")
        XCTAssertEqual(routeEvent.engine, "coreml")
        XCTAssertTrue(routeEvent.fallbackUsed)
        XCTAssertEqual(routeEvent.fallbackTriggerCode, "gate_failed")
        XCTAssertEqual(routeEvent.candidateAttempts, 3)
        XCTAssertEqual(routeEvent.modelRefKind, "deployment_ref")
    }

    func testRouteEventEncodesAsJSON() throws {
        let routeEvent = RouteEvent(
            routeId: "route_test",
            requestId: "req_test",
            planId: nil,
            capability: "chat",
            policy: "auto",
            plannerSource: "none",
            finalLocality: "cloud",
            engine: nil,
            fallbackUsed: false,
            candidateAttempts: 1,
            modelRefKind: "plain_id"
        )

        let data = try JSONEncoder().encode(routeEvent)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify wire format keys match contract snake_case
        XCTAssertEqual(json["route_id"] as? String, "route_test")
        XCTAssertEqual(json["request_id"] as? String, "req_test")
        XCTAssertEqual(json["capability"] as? String, "chat")
        XCTAssertEqual(json["final_locality"] as? String, "cloud")
        XCTAssertEqual(json["fallback_used"] as? Bool, false)
        XCTAssertEqual(json["candidate_attempts"] as? Int, 1)
        XCTAssertEqual(json["model_ref_kind"] as? String, "plain_id")
    }

    func testRouteEventNeverContainsPromptOrOutput() throws {
        // Critical privacy check: RouteEvent must never contain content fields.
        let routeEvent = RouteEvent(
            routeId: "route_privacy",
            requestId: "req_privacy",
            capability: "chat",
            finalLocality: "local",
            modelRefKind: "plain_id"
        )

        let data = try JSONEncoder().encode(routeEvent)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let keys = Set(json.keys)

        // These content keys must NEVER appear in a RouteEvent
        let forbiddenKeys: Set<String> = [
            "prompt", "input", "output", "messages", "content",
            "audio", "file_path", "filePath", "text", "response_text",
        ]
        let leaked = keys.intersection(forbiddenKeys)
        XCTAssertTrue(leaked.isEmpty, "RouteEvent must not contain content keys: \(leaked)")
    }

    func testTelemetryQueueReportsRouteEvent() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: URL(string: "https://test.local")!,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: tempDir.appendingPathComponent("events.json")
        )

        let routeEvent = RouteEvent(
            routeId: "route_tel",
            requestId: "req_tel",
            planId: "plan_tel",
            capability: "chat",
            policy: "local_first",
            plannerSource: "cache",
            finalLocality: "local",
            engine: "coreml",
            fallbackUsed: false,
            candidateAttempts: 2,
            modelRefKind: "plain_id"
        )

        queue.reportRouteEvent(routeEvent)

        let events = queue.bufferedEvents.filter { $0.name == "route.completed" }
        XCTAssertEqual(events.count, 1, "Must record exactly one route.completed event")

        let attrs = events[0].attributes
        XCTAssertEqual(attrs["route.id"], .string("route_tel"))
        XCTAssertEqual(attrs["request.id"], .string("req_tel"))
        XCTAssertEqual(attrs["route.plan_id"], .string("plan_tel"))
        XCTAssertEqual(attrs["route.capability"], .string("chat"))
        XCTAssertEqual(attrs["route.policy"], .string("local_first"))
        XCTAssertEqual(attrs["route.planner_source"], .string("cache"))
        XCTAssertEqual(attrs["route.final_locality"], .string("local"))
        XCTAssertEqual(attrs["route.engine"], .string("coreml"))
        XCTAssertEqual(attrs["route.fallback_used"], .bool(false))
        XCTAssertEqual(attrs["route.candidate_attempts"], .int(2))
        XCTAssertEqual(attrs["route.model_ref_kind"], .string("plain_id"))

        // Privacy check: no content fields in telemetry attributes
        let forbiddenPrefixes = ["prompt", "input", "output", "content", "audio", "file"]
        for key in attrs.keys {
            for prefix in forbiddenPrefixes {
                XCTAssertFalse(
                    key.hasPrefix(prefix),
                    "Telemetry attribute key '\(key)' must not start with '\(prefix)'"
                )
            }
        }
    }

    // MARK: - 5. Routing policy semantics

    func testLocalOnlyPolicyBlocksFallback() {
        XCTAssertFalse(RequestRouter.isFallbackAllowed(.localOnly))
    }

    func testPrivatePolicyBlocksFallback() {
        XCTAssertFalse(RequestRouter.isFallbackAllowed(.private))
    }

    func testLocalFirstPolicyAllowsFallback() {
        XCTAssertTrue(RequestRouter.isFallbackAllowed(.localFirst))
    }

    func testCloudFirstPolicyAllowsFallback() {
        XCTAssertTrue(RequestRouter.isFallbackAllowed(.cloudFirst))
    }

    func testNilPolicyAllowsFallback() {
        XCTAssertTrue(RequestRouter.isFallbackAllowed(nil))
    }

    // MARK: - 6. Plan-based routing with cached plan

    func testRoutingWithCachedPlanUsesCorrectPlannerSource() {
        let plan = RuntimePlanResponse(
            model: "phi-4-mini",
            capability: "chat",
            policy: "local_first",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 0,
                    confidence: 0.9,
                    reason: "coreml available",
                    engine: "coreml"
                ),
            ]
        )

        let router = RequestRouter()
        let context = RequestRoutingContext(
            model: "phi-4-mini",
            capability: "chat",
            streaming: false,
            cachedPlan: plan
        )

        let decision = router.resolve(context: context)
        XCTAssertEqual(decision.routeMetadata.plannerSource, "cache")
    }

    // MARK: - 7. Auth safety — publishable key only in app-facing code

    func testPublishableKeyValidation() {
        // Valid keys
        let testKey = AuthConfig.validatedPublishableKey("oct_pub_test_abc123")
        XCTAssertEqual(testKey.token, "oct_pub_test_abc123")
        XCTAssertEqual(testKey.publishableKeyEnvironment, "test")

        let liveKey = AuthConfig.validatedPublishableKey("oct_pub_live_xyz789")
        XCTAssertEqual(liveKey.token, "oct_pub_live_xyz789")
        XCTAssertEqual(liveKey.publishableKeyEnvironment, "live")
    }

    func testAnonymousAuthHasEmptyToken() {
        let auth = AuthConfig.anonymous(appId: "com.test.app")
        XCTAssertEqual(auth.token, "")
    }
}

// MARK: - Test Helpers

private enum TestRoutingError: Error {
    case inferenceFailedAfterFirstToken
}

private final class RoutingMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let response: RuntimeResponse

    init(response: RuntimeResponse) { self.response = response }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse { response }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class RoutingStreamMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    let chunks: [RuntimeChunk]

    init(chunks: [RuntimeChunk]) { self.chunks = chunks }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse { RuntimeResponse(text: "") }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
    func close() {}
}

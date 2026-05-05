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
        XCTAssertEqual(meta.status, "selected")
        XCTAssertNotNil(meta.execution)
        XCTAssertEqual(meta.model.requested.kind.rawValue, "model")
        XCTAssertEqual(meta.model.requested.ref, "phi-4-mini")
        XCTAssertFalse(meta.execution?.locality.isEmpty ?? true)
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
        XCTAssertEqual(meta.status, "selected")
        XCTAssertEqual(meta.model.requested.kind.rawValue, "model")
    }

    func testRouteMetadataContainsPlannerSource() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "ok"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "test-model", input: [.text("Hi")])
        )

        let meta = response.routeMetadata!
        // Without a cached server plan, planner source should be offline.
        XCTAssertEqual(meta.planner.source, "offline")
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
        let ref = ParsedModelRef.parse("deploy_abc123")
        XCTAssertEqual(ref.kind, .deployment)
        XCTAssertEqual(ref.raw, "deploy_abc123")
        XCTAssertEqual(ref.deploymentId, "deploy_abc123")
    }

    func testExperimentRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("exp_variant_42/a")
        XCTAssertEqual(ref.kind, .experiment)
        XCTAssertEqual(ref.raw, "exp_variant_42/a")
        XCTAssertEqual(ref.experimentId, "exp_variant_42")
        XCTAssertEqual(ref.variantId, "a")
    }

    func testAppRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("@app/myapp/chat")
        XCTAssertEqual(ref.kind, .app)
        XCTAssertEqual(ref.raw, "@app/myapp/chat")
        XCTAssertEqual(ref.appSlug, "myapp")
        XCTAssertEqual(ref.capability, "chat")
    }

    func testCapabilityRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("@capability/chat")
        XCTAssertEqual(ref.kind, .capability)
        XCTAssertEqual(ref.raw, "@capability/chat")
        XCTAssertEqual(ref.capability, "chat")
    }

    func testPlainIdParsedCorrectly() {
        let ref = ParsedModelRef.parse("phi-4-mini")
        XCTAssertEqual(ref.kind, .model)
        XCTAssertEqual(ref.raw, "phi-4-mini")
    }

    func testAliasRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("alias:my-model")
        XCTAssertEqual(ref.kind, .alias)
        XCTAssertEqual(ref.raw, "alias:my-model")
    }

    func testUnknownScopedRefParsedCorrectly() {
        let ref = ParsedModelRef.parse("@unknown/scope")
        XCTAssertEqual(ref.kind, .unknown)
        XCTAssertEqual(ref.raw, "@unknown/scope")
    }

    func testDeploymentRefCarriedInRouteMetadata() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "deployed"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "deploy_deployment_123", input: [.text("Hi")])
        )

        XCTAssertEqual(
            response.routeMetadata?.model.requested.kind.rawValue, "deployment",
            "Route metadata must reflect the deployment ref kind"
        )
    }

    func testExperimentRefCarriedInRouteMetadata() async throws {
        let runtime = RoutingMockRuntime(response: RuntimeResponse(text: "experiment"))
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        let response = try await responses.create(
            ResponseRequest(model: "exp_variant_42/a", input: [.text("Hi")])
        )

        XCTAssertEqual(
            response.routeMetadata?.model.requested.kind.rawValue, "experiment",
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
            response.routeMetadata?.model.requested.kind.rawValue, "app",
            "Route metadata must reflect the app ref kind"
        )
    }

    func testDeploymentRefRoutesViaRequestRouter() {
        let router = RequestRouter()
        let context = RequestRoutingContext(
            model: "deploy_456",
            capability: "chat",
            streaming: false
        )
        let decision = router.resolve(context: context)

        // Without a plan, should fall back to hosted gateway
        XCTAssertEqual(decision.routeMetadata.model.requested.kind.rawValue, "deployment")
        XCTAssertEqual(decision.locality, "cloud")
        XCTAssertEqual(decision.mode, "hosted_gateway")
    }

    func testExperimentRefRoutesViaRequestRouter() {
        let router = RequestRouter()
        let context = RequestRoutingContext(
            model: "exp_variant_99/b",
            capability: "chat",
            streaming: false
        )
        let decision = router.resolve(context: context)

        XCTAssertEqual(decision.routeMetadata.model.requested.kind.rawValue, "experiment")
    }

    func testStreamWithDeploymentRefAttachesCorrectKind() async throws {
        let runtime = RoutingStreamMockRuntime(chunks: [RuntimeChunk(text: "result")])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        var doneResponse: Response?
        for try await event in responses.stream(
            ResponseRequest(model: "deploy_xyz789", input: [.text("query")])
        ) {
            if case .done(let resp) = event {
                doneResponse = resp
            }
        }

        XCTAssertNotNil(doneResponse)
        XCTAssertEqual(doneResponse?.routeMetadata?.model.requested.kind.rawValue, "deployment")
    }

    func testStreamWithAppRefAttachesCorrectKind() async throws {
        let runtime = RoutingStreamMockRuntime(chunks: [RuntimeChunk(text: "result")])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        var doneResponse: Response?
        for try await event in responses.stream(
            ResponseRequest(model: "@app/myapp/chat", input: [.text("query")])
        ) {
            if case .done(let resp) = event {
                doneResponse = resp
            }
        }

        XCTAssertNotNil(doneResponse)
        XCTAssertEqual(doneResponse?.routeMetadata?.model.requested.kind.rawValue, "app")
    }

    func testStreamWithExperimentRefAttachesCorrectKind() async throws {
        let runtime = RoutingStreamMockRuntime(chunks: [RuntimeChunk(text: "result")])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })

        var doneResponse: Response?
        for try await event in responses.stream(
            ResponseRequest(model: "exp_abc/variant_b", input: [.text("query")])
        ) {
            if case .done(let resp) = event {
                doneResponse = resp
            }
        }

        XCTAssertNotNil(doneResponse)
        XCTAssertEqual(doneResponse?.routeMetadata?.model.requested.kind.rawValue, "experiment")
    }

    // MARK: - 4. Telemetry event matches contract shape

    func testRouteEventFromDecisionHasCanonicalFields() {
        let metadata = RouteMetadata(
            status: "selected",
            execution: RouteExecution(locality: "local", mode: "sdk_runtime", engine: "coreml"),
            model: RouteModel(
                requested: RouteModelRequested(ref: "deploy_abc", kind: .deployment, capability: nil),
                resolved: nil
            ),
            artifact: RouteArtifact(id: nil, version: nil, format: nil, digest: nil, cache: ArtifactCache(status: "hit", managed_by: nil)),
            planner: PlannerInfo(source: "cache"),
            fallback: FallbackInfo(used: true, from_attempt: nil, to_attempt: nil, trigger: nil),
            attempts: nil,
            reason: RouteReason(code: "ok", message: "")
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
        XCTAssertTrue(routeEvent.routeId.hasPrefix("route_"))
        XCTAssertEqual(routeEvent.requestId, "req_xyz")
        XCTAssertNil(routeEvent.planId)
        XCTAssertEqual(routeEvent.capability, "chat")
        XCTAssertNil(routeEvent.policy)
        XCTAssertEqual(routeEvent.plannerSource, "cache")
        XCTAssertEqual(routeEvent.finalLocality, "local")
        XCTAssertEqual(routeEvent.engine, "coreml")
        XCTAssertTrue(routeEvent.fallbackUsed)
        XCTAssertNil(routeEvent.fallbackTriggerCode)
        XCTAssertEqual(routeEvent.candidateAttempts, 0)
        XCTAssertEqual(routeEvent.modelRef, "deploy_abc")
        XCTAssertEqual(routeEvent.modelRefKind, "deployment")
        XCTAssertEqual(routeEvent.cacheStatus, "hit")
    }

    func testRouteEventEncodesAsJSON() throws {
        let routeEvent = RouteEvent(
            routeId: "route_test",
            requestId: "req_test",
            planId: nil,
            capability: "chat",
            policy: "auto",
            plannerSource: "none",
            selectedLocality: "cloud",
            finalMode: "hosted_gateway",
            engine: nil,
            fallbackUsed: false,
            candidateAttempts: 1,
            modelRefKind: "model"
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
        XCTAssertEqual(json["model_ref_kind"] as? String, "model")
    }

    func testRouteEventNeverContainsPromptOrOutput() throws {
        // Critical privacy check: RouteEvent must never contain content fields.
        let routeEvent = RouteEvent(
            routeId: "route_privacy",
            requestId: "req_privacy",
            capability: "chat",
            selectedLocality: "local",
            finalMode: "sdk_runtime",
            modelRefKind: "model"
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
            selectedLocality: "local",
            finalMode: "sdk_runtime",
            engine: "coreml",
            fallbackUsed: false,
            candidateAttempts: 2,
            modelRefKind: "model",
            cacheStatus: "hit"
        )

        queue.reportRouteEvent(routeEvent)

        let events = queue.bufferedEvents.filter { $0.name == "route.decision" }
        XCTAssertEqual(events.count, 1, "Must record exactly one route.decision event")

        let attrs = events[0].attributes
        XCTAssertEqual(attrs["route.id"], .string("route_tel"))
        XCTAssertEqual(attrs["route.request_id"], .string("req_tel"))
        XCTAssertEqual(attrs["route.plan_id"], .string("plan_tel"))
        XCTAssertEqual(attrs["route.capability"], .string("chat"))
        XCTAssertEqual(attrs["route.policy"], .string("local_first"))
        XCTAssertEqual(attrs["route.planner_source"], .string("cache"))
        XCTAssertEqual(attrs["route.final_locality"], .string("local"))
        XCTAssertEqual(attrs["route.selected_locality"], .string("local"))
        XCTAssertEqual(attrs["route.engine"], .string("coreml"))
        XCTAssertEqual(attrs["route.fallback_used"], .bool(false))
        XCTAssertEqual(attrs["route.candidate_attempts"], .int(2))
        XCTAssertEqual(attrs["route.model_ref_kind"], .string("model"))
        XCTAssertEqual(attrs["route.cache_status"], .string("hit"))

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
        XCTAssertEqual(decision.routeMetadata.planner.source, "cache")
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

import XCTest
@testable import Octomil

/// Conformance tests verifying that RequestRouter exposes one contract-backed
/// RouteMetadata shape on `decision.routeMetadata`.
final class CanonicalRouteSurfaceTests: XCTestCase {

    func testRouteMetadataPopulatedOnDefaultResolution() {
        let router = RequestRouter()
        let decision = router.resolve(
            context: RequestRoutingContext(model: "phi-4", capability: "chat")
        )

        let meta = decision.routeMetadata
        XCTAssertEqual(meta.status, "selected")
        XCTAssertNotNil(meta.execution)
        XCTAssertEqual(meta.execution?.locality, "cloud")
        XCTAssertEqual(meta.execution?.mode, "hosted_gateway")
        XCTAssertEqual(meta.model.requested.ref, "phi-4")
        XCTAssertEqual(meta.model.requested.kind.rawValue, "model")
        XCTAssertEqual(meta.planner.source, "offline")
        XCTAssertEqual(meta.fallback.used, false)
    }

    func testRouteMetadataPopulatedOnPlanBasedResolution() {
        let router = RequestRouter()
        let plan = RuntimePlanResponse(
            model: "phi-4",
            capability: "chat",
            policy: "cloud_only",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .cloud,
                    priority: 0,
                    confidence: 1.0,
                    reason: "test"
                ),
            ]
        )
        let decision = router.resolve(
            context: RequestRoutingContext(
                model: "phi-4",
                capability: "chat",
                cachedPlan: plan
            )
        )

        let meta = decision.routeMetadata
        XCTAssertEqual(meta.status, "selected")
        XCTAssertEqual(meta.execution?.locality, "cloud")
        XCTAssertEqual(meta.planner.source, "cache")
    }

    func testRouteMetadataHasContractRequiredStructure() {
        let router = RequestRouter()
        let decision = router.resolve(
            context: RequestRoutingContext(model: "@app/myapp/chat", capability: "chat")
        )

        let meta = decision.routeMetadata
        XCTAssertEqual(meta.status, "selected")
        XCTAssertNotNil(meta.execution)
        XCTAssertEqual(meta.model.requested.ref, "@app/myapp/chat")
        XCTAssertEqual(meta.model.requested.kind.rawValue, "app")
        XCTAssertFalse(meta.planner.source.isEmpty)
        XCTAssertEqual(meta.fallback.used, false)
    }

    func testReportsUnavailableWhenNoRouteFound() {
        let router = RequestRouter()
        let plan = RuntimePlanResponse(
            model: "phi-4",
            capability: "chat",
            policy: "local_only",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 0,
                    confidence: 1.0,
                    reason: "test",
                    engine: "coreml"
                ),
            ],
            fallbackAllowed: false
        )
        let decision = router.resolve(
            context: RequestRoutingContext(
                model: "phi-4",
                capability: "chat",
                cachedPlan: plan,
                routingPolicy: .localOnly
            ),
            runtimeChecker: RejectAllRuntimeChecker()
        )

        let meta = decision.routeMetadata
        XCTAssertEqual(meta.status, "unavailable")
        XCTAssertNil(meta.execution)
    }
}

private struct RejectAllRuntimeChecker: AttemptRuntimeChecker {
    func check(engine: String?, locality: String) -> (available: Bool, reasonCode: String?) {
        (false, "test_reject")
    }
}

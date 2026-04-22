import XCTest
@testable import Octomil

/// Conformance tests verifying that RequestRouter populates the contract-backed
/// canonicalMetadata field alongside the deprecated flat routeMetadata,
/// and that both shapes agree on key fields.
final class CanonicalRouteSurfaceTests: XCTestCase {

    // MARK: - Default (no plan) resolution

    func testCanonicalMetadataPopulatedOnDefaultResolution() {
        let router = RequestRouter()
        let decision = router.resolve(
            context: RequestRoutingContext(model: "phi-4", capability: "chat")
        )

        let meta = decision.canonicalMetadata
        XCTAssertEqual(meta.status, "selected")
        XCTAssertNotNil(meta.execution)
        XCTAssertEqual(meta.execution?.locality, "cloud")
        XCTAssertEqual(meta.execution?.mode, "hosted_gateway")
        XCTAssertEqual(meta.model.requested.ref, "phi-4")
        XCTAssertEqual(meta.model.requested.kind, "model")
        XCTAssertEqual(meta.planner.source, "offline")
        XCTAssertEqual(meta.fallback.used, false)
    }

    // MARK: - Plan-based resolution

    func testCanonicalMetadataPopulatedOnPlanBasedResolution() {
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

        let meta = decision.canonicalMetadata
        XCTAssertEqual(meta.status, "selected")
        XCTAssertEqual(meta.execution?.locality, "cloud")
        XCTAssertEqual(meta.planner.source, "cache")
    }

    // MARK: - Contract-required nested structure

    func testCanonicalMetadataHasContractRequiredStructure() {
        let router = RequestRouter()
        let decision = router.resolve(
            context: RequestRoutingContext(model: "@app/myapp/chat", capability: "chat")
        )

        let meta = decision.canonicalMetadata

        // All top-level contract fields present
        XCTAssertEqual(meta.status, "selected")
        XCTAssertNotNil(meta.execution)
        // model is always non-optional
        XCTAssertEqual(meta.model.requested.ref, "@app/myapp/chat")
        XCTAssertEqual(meta.model.requested.kind, "app")
        // planner, fallback, reason are always present (non-optional)
        XCTAssertFalse(meta.planner.source.isEmpty)
        // fallback.used is a Bool (non-optional)
        XCTAssertEqual(meta.fallback.used, false)
    }

    // MARK: - Unavailable when no route found

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
        // Resolve with local_only policy + a checker that rejects all engines.
        let decision = router.resolve(
            context: RequestRoutingContext(
                model: "phi-4",
                capability: "chat",
                cachedPlan: plan,
                routingPolicy: .localOnly
            ),
            runtimeChecker: RejectAllRuntimeChecker()
        )

        let meta = decision.canonicalMetadata
        XCTAssertEqual(meta.status, "unavailable")
        XCTAssertNil(meta.execution)
    }

    // MARK: - Backward compatibility

    func testFlatRouteMetadataStillPopulated() {
        let router = RequestRouter()
        let decision = router.resolve(
            context: RequestRoutingContext(model: "phi-4", capability: "chat")
        )

        // The flat shape is deprecated but must still be populated for backward compat.
        XCTAssertEqual(decision.locality, "cloud")
        XCTAssertEqual(decision.mode, "hosted_gateway")
    }

    func testBothShapesAgreeOnStatusAndLocality() {
        let router = RequestRouter()
        let decision = router.resolve(
            context: RequestRoutingContext(model: "phi-4", capability: "chat")
        )

        // Both shapes agree on locality.
        let canonical = decision.canonicalMetadata
        XCTAssertEqual(canonical.execution?.locality, decision.locality)
        XCTAssertEqual(canonical.execution?.mode, decision.mode)
    }
}

// MARK: - Test Helpers

/// Runtime checker that rejects all engines, forcing the attempt loop to fail.
private struct RejectAllRuntimeChecker: AttemptRuntimeChecker {
    func check(engine: String?, locality: String) -> (available: Bool, reasonCode: String?) {
        (false, "test_reject")
    }
}

import XCTest
@testable import Octomil

final class PlannerRoutingDefaultsTests: XCTestCase {

    // MARK: - Default behavior: planner ON with credentials

    func testPlannerEnabledByDefaultWithOrgApiKey() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: nil,
            auth: .orgApiKey(apiKey: "edg_test_123", orgId: "org_abc")
        )
        XCTAssertTrue(result, "Planner should be ON when OrgApiKey credentials exist")
    }

    func testPlannerEnabledByDefaultWithPublishableKey() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: nil,
            auth: .publishableKey("oct_pub_test_abc123")
        )
        XCTAssertTrue(result, "Planner should be ON when PublishableKey credentials exist")
    }

    func testPlannerEnabledByDefaultWithDeviceToken() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: nil,
            auth: .deviceToken(deviceId: "dev_123", bootstrapToken: "bt_test")
        )
        XCTAssertTrue(result, "Planner should be ON when DeviceToken credentials exist")
    }

    // MARK: - Default behavior: planner OFF without credentials

    func testPlannerDisabledByDefaultWithAnonymous() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: nil,
            auth: .anonymous(appId: "com.test.app")
        )
        XCTAssertFalse(result, "Planner should be OFF with Anonymous auth")
    }

    func testPlannerDisabledByDefaultWithEmptyApiKey() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: nil,
            auth: .orgApiKey(apiKey: "", orgId: "org_abc")
        )
        XCTAssertFalse(result, "Planner should be OFF when apiKey is empty")
    }

    func testPlannerDisabledByDefaultWithEmptyPublishableKey() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: nil,
            auth: .publishableKey("")
        )
        XCTAssertFalse(result, "Planner should be OFF when publishableKey is empty")
    }

    // MARK: - Explicit override

    func testExplicitFalseDisablesPlannerEvenWithCredentials() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: false,
            auth: .orgApiKey(apiKey: "edg_test_123", orgId: "org_abc")
        )
        XCTAssertFalse(result, "Explicit false should disable planner")
    }

    func testExplicitTrueEnablesPlannerEvenWithoutCredentials() {
        let result = PlannerRoutingDefaults.resolve(
            explicitOverride: true,
            auth: .anonymous(appId: "com.test.app")
        )
        XCTAssertTrue(result, "Explicit true should enable planner")
    }

    // MARK: - Privacy: private and local_only block cloud

    func testPrivatePolicyBlocksCloud() {
        XCTAssertTrue(PlannerRoutingDefaults.isCloudBlocked(policy: .private))
    }

    func testLocalOnlyPolicyBlocksCloud() {
        XCTAssertTrue(PlannerRoutingDefaults.isCloudBlocked(policy: .localOnly))
    }

    func testCloudFirstPolicyDoesNotBlockCloud() {
        XCTAssertFalse(PlannerRoutingDefaults.isCloudBlocked(policy: .cloudFirst))
    }

    func testLocalFirstPolicyDoesNotBlockCloud() {
        XCTAssertFalse(PlannerRoutingDefaults.isCloudBlocked(policy: .localFirst))
    }

    func testNilPolicyDoesNotBlockCloud() {
        XCTAssertFalse(PlannerRoutingDefaults.isCloudBlocked(policy: nil))
    }

    // MARK: - Default policy

    func testDefaultPolicyAutoWhenPlannerEnabled() {
        XCTAssertEqual(PlannerRoutingDefaults.defaultPolicy(plannerEnabled: true), .auto)
    }

    func testDefaultPolicyLocalFirstWhenPlannerDisabled() {
        XCTAssertEqual(PlannerRoutingDefaults.defaultPolicy(plannerEnabled: false), .localFirst)
    }
}

import XCTest
@testable import Octomil

/// Tests for the shouldAutoRegister logic in OctomilClient.configure().
///
/// The gate: `auth != nil && (manifest has managed/cloud models || monitoring.enabled)`
///
/// Since the gate is inline in configure(), we test the logic by verifying
/// the same boolean expression against different inputs.
final class RegistrationGateTests: XCTestCase {

    // MARK: - Helpers

    private func shouldAutoRegister(
        auth: AuthConfig?,
        manifest: AppManifest,
        monitoring: MonitoringConfig
    ) -> Bool {
        auth != nil && (
            manifest.models.contains { $0.delivery == .managed || $0.delivery == .cloud }
            || monitoring.enabled
        )
    }

    private let managedModel = AppModelEntry(
        id: "phi-4-mini",
        capability: .chat,
        delivery: .managed
    )

    private let cloudModel = AppModelEntry(
        id: "gpt-proxy",
        capability: .chat,
        delivery: .cloud
    )

    private let bundledModel = AppModelEntry(
        id: "whisper-base",
        capability: .transcription,
        delivery: .bundled,
        bundledPath: "Models/whisper.mlmodelc"
    )

    // MARK: - Tests

    func testAuthPresentAndMonitoringEnabled() {
        let result = shouldAutoRegister(
            auth: .publishableKey("oct_pub_test"),
            manifest: AppManifest(models: [bundledModel]),
            monitoring: .enabled
        )
        XCTAssertTrue(result)
    }

    func testAuthPresentAndManagedModel() {
        let result = shouldAutoRegister(
            auth: .publishableKey("oct_pub_test"),
            manifest: AppManifest(models: [managedModel]),
            monitoring: .disabled
        )
        XCTAssertTrue(result)
    }

    func testAuthPresentAndCloudModel() {
        let result = shouldAutoRegister(
            auth: .publishableKey("oct_pub_test"),
            manifest: AppManifest(models: [cloudModel]),
            monitoring: .disabled
        )
        XCTAssertTrue(result)
    }

    func testAuthPresentNoManagedModelsNoMonitoring() {
        let result = shouldAutoRegister(
            auth: .publishableKey("oct_pub_test"),
            manifest: AppManifest(models: [bundledModel]),
            monitoring: .disabled
        )
        XCTAssertFalse(result)
    }

    func testNoAuth() {
        let result = shouldAutoRegister(
            auth: nil,
            manifest: AppManifest(models: [managedModel]),
            monitoring: .enabled
        )
        XCTAssertFalse(result)
    }

    func testEmptyManifestWithMonitoringEnabled() {
        let result = shouldAutoRegister(
            auth: .anonymous(appId: "com.test"),
            manifest: AppManifest(models: []),
            monitoring: .enabled
        )
        XCTAssertTrue(result)
    }

    func testEmptyManifestNoMonitoring() {
        let result = shouldAutoRegister(
            auth: .anonymous(appId: "com.test"),
            manifest: AppManifest(models: []),
            monitoring: .disabled
        )
        XCTAssertFalse(result)
    }

    func testBootstrapTokenWithManagedModel() {
        let result = shouldAutoRegister(
            auth: .deviceToken(deviceId: "dev_123", bootstrapToken: "jwt-tok"),
            manifest: AppManifest(models: [managedModel, bundledModel]),
            monitoring: .disabled
        )
        XCTAssertTrue(result)
    }
}

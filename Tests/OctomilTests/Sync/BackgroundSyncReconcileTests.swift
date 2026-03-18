#if os(iOS)
import XCTest
@testable import Octomil

final class BackgroundSyncReconcileTests: XCTestCase {

    // MARK: - isReconcileEnabled

    func testIsReconcileEnabledDefaultsFalse() {
        // BackgroundSync.shared is a singleton, but we can verify
        // reconcileEnabled is false by default when not configured
        let sync = BackgroundSync.shared
        // Without configuring reconciler, isReconcileEnabled should be false
        // Note: This tests the property, not the full flow, since we can't
        // invoke BGTaskScheduler in unit tests.
        XCTAssertFalse(sync.isReconcileEnabled)
    }

    func testConfigureReconcilerEnablesSync() {
        let config = TestConfiguration.fast()
        let apiClient = APIClient(serverURL: URL(string: "https://test.octomil.com")!, configuration: config)
        let controlSync = ControlSync(apiClient: apiClient)
        let store = ModelMetadataStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("bg-test-\(UUID().uuidString).json")
        )
        let reconciler = ArtifactReconciler(
            controlSync: controlSync,
            metadataStore: store,
            artifactDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("bg-test-artifacts-\(UUID().uuidString)")
        )

        let sync = BackgroundSync.shared
        sync.configureReconciler(reconciler: reconciler, deviceId: "test-device-123")

        XCTAssertTrue(sync.isReconcileEnabled)
    }
}
#endif

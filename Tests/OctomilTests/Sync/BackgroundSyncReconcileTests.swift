#if os(iOS)
import XCTest
@testable import Octomil

final class BackgroundSyncReconcileTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // ``BackgroundSync.shared`` is a process-wide singleton.
        // The companion test in this suite calls
        // ``configureReconciler`` and the configured state leaks
        // forward, making this test flake when XCTest runs them
        // in alphabetical order (configure-… first, defaults-…
        // second). Reset before every test in this suite so each
        // case sees a deterministic empty state.
        BackgroundSync.shared._resetReconcilerForTesting()
    }

    override func tearDown() {
        BackgroundSync.shared._resetReconcilerForTesting()
        super.tearDown()
    }

    // MARK: - isReconcileEnabled

    func testIsReconcileEnabledDefaultsFalse() {
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

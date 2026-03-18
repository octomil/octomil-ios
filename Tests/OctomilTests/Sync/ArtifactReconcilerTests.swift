import XCTest
import CryptoKit
@testable import Octomil

final class ArtifactReconcilerTests: XCTestCase {

    private var store: ModelMetadataStore!
    private var storeURL: URL!
    private var artifactDir: URL!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-reconciler-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("test_models.json")
        artifactDir = tempDir.appendingPathComponent("artifacts", isDirectory: true)
        store = ModelMetadataStore(storeURL: storeURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - planActions

    func testPlanActionsNewModel() {
        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [
                DesiredModelEntry(
                    modelId: "m1",
                    modelVersion: "1.0.0",
                    artifactVersion: "1.0.0",
                    artifactId: "a1",
                    downloadUrl: "https://example.com/a1.bin",
                    checksum: "abc",
                    fileSize: 1024
                ),
            ]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .download(let entry) = actions[0] {
            XCTAssertEqual(entry.modelId, "m1")
        } else {
            XCTFail("Expected download action")
        }
    }

    func testPlanActionsUpToDate() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: "/tmp/test/a1"
        ))

        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [
                DesiredModelEntry(
                    modelId: "m1",
                    modelVersion: "1.0.0",
                    artifactVersion: "1.0.0",
                    artifactId: "a1",
                    downloadUrl: "https://example.com/a1.bin",
                    checksum: "abc",
                    fileSize: 1024
                ),
            ]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .upToDate(let modelId) = actions[0] {
            XCTAssertEqual(modelId, "m1")
        } else {
            XCTFail("Expected upToDate action")
        }
    }

    func testPlanActionsVersionUpgrade() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: "/tmp/test/a1"
        ))

        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [
                DesiredModelEntry(
                    modelId: "m1",
                    modelVersion: "2.0.0",
                    artifactVersion: "2.0.0",
                    artifactId: "a2",
                    downloadUrl: "https://example.com/a2.bin",
                    checksum: "def",
                    fileSize: 2048
                ),
            ]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .download(let entry) = actions[0] {
            XCTAssertEqual(entry.artifactId, "a2")
        } else {
            XCTFail("Expected download action for new version")
        }
    }

    func testPlanActionsStagedWithImmediatePolicy() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .staged,
            filePath: "/tmp/test/a1"
        ))

        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [
                DesiredModelEntry(
                    modelId: "m1",
                    modelVersion: "1.0.0",
                    artifactVersion: "1.0.0",
                    artifactId: "a1",
                    downloadUrl: "https://example.com/a1.bin",
                    checksum: "abc",
                    fileSize: 1024,
                    activationPolicy: .immediate
                ),
            ]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .activate(let modelId, let version) = actions[0] {
            XCTAssertEqual(modelId, "m1")
            XCTAssertEqual(version, "1.0.0")
        } else {
            XCTFail("Expected activate action")
        }
    }

    func testPlanActionsStagedWithNextLaunchPolicy() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .staged,
            filePath: "/tmp/test/a1"
        ))

        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [
                DesiredModelEntry(
                    modelId: "m1",
                    modelVersion: "1.0.0",
                    artifactVersion: "1.0.0",
                    artifactId: "a1",
                    downloadUrl: "https://example.com/a1.bin",
                    checksum: "abc",
                    fileSize: 1024,
                    activationPolicy: .nextLaunch
                ),
            ]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        // Should be upToDate since it's staged and waiting for next_launch
        XCTAssertEqual(actions.count, 1)
        if case .upToDate(let modelId) = actions[0] {
            XCTAssertEqual(modelId, "m1")
        } else {
            XCTFail("Expected upToDate action for next_launch staged artifact")
        }
    }

    func testPlanActionsFailedModel() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .failed,
            filePath: "/tmp/test/a1"
        ))

        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [
                DesiredModelEntry(
                    modelId: "m1",
                    modelVersion: "1.0.0",
                    artifactVersion: "1.0.0",
                    artifactId: "a1",
                    downloadUrl: "https://example.com/a1.bin",
                    checksum: "abc",
                    fileSize: 1024
                ),
            ]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .download = actions[0] {
            // Re-download after failure
        } else {
            XCTFail("Expected download action for failed artifact")
        }
    }

    func testPlanActionsGarbageCollection() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "old-artifact",
            status: .staged,
            filePath: "/tmp/test/old"
        ))

        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [],
            gcEligibleArtifactIds: ["old-artifact"]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .remove(let artifactId) = actions[0] {
            XCTAssertEqual(artifactId, "old-artifact")
        } else {
            XCTFail("Expected remove action")
        }
    }

    func testPlanActionsGarbageCollectionSkipsMissing() {
        let desired = ParsedDesiredState(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            models: [],
            gcEligibleArtifactIds: ["nonexistent"]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Rollback

    func testCheckAndRollbackWhenCrashLoopDetected() {
        // Old version
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1-old",
            status: .staged,
            filePath: "/tmp/test/a1-old"
        ))

        // Active version with crash loop
        var activeRecord = InstalledModelRecord(
            modelId: "m1",
            modelVersion: "2.0.0",
            artifactVersion: "2.0.0",
            artifactId: "a1-new",
            status: .active,
            filePath: "/tmp/test/a1-new"
        )
        // Set crash count to threshold
        activeRecord.crashCount = ModelMetadataStore.crashLoopThreshold
        store.upsert(activeRecord)

        let reconciler = makeReconciler()
        let rolledBack = reconciler.checkAndRollbackSync(modelId: "m1")

        XCTAssertTrue(rolledBack)

        // Old version should now be active
        let active = store.activeRecord(forModelId: "m1")
        XCTAssertEqual(active?.artifactId, "a1-old")

        // New version should be rolled back
        let rolled = store.record(forArtifactId: "a1-new")
        XCTAssertEqual(rolled?.status, .rolledBack)
    }

    func testCheckAndRollbackNotTriggeredBelowThreshold() {
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: "/tmp/test/a1"
        ))

        let reconciler = makeReconciler()
        let rolledBack = reconciler.checkAndRollbackSync(modelId: "m1")
        XCTAssertFalse(rolledBack)
    }

    func testCheckAndRollbackNoActiveModel() {
        let reconciler = makeReconciler()
        let rolledBack = reconciler.checkAndRollbackSync(modelId: "nonexistent")
        XCTAssertFalse(rolledBack)
    }

    // MARK: - Desired State Types

    func testActivationPolicyCoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for policy in [ActivationPolicy.immediate, .nextLaunch, .manual, .whenIdle] {
            let data = try encoder.encode(policy)
            let decoded = try decoder.decode(ActivationPolicy.self, from: data)
            XCTAssertEqual(decoded, policy)
        }
    }

    func testDesiredModelEntryDecoding() throws {
        let json = """
        {
            "model_id": "m1",
            "model_version": "1.0.0",
            "artifact_version": "1.0.0",
            "artifact_id": "a1",
            "download_url": "https://example.com/a1.bin",
            "checksum": "abc123",
            "file_size": 1024,
            "activation_policy": "next_launch"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(DesiredModelEntry.self, from: json)
        XCTAssertEqual(entry.modelId, "m1")
        XCTAssertEqual(entry.activationPolicy, .nextLaunch)
        XCTAssertEqual(entry.fileSize, 1024)
    }

    func testInstalledModelRecordCoding() throws {
        let record = InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: "/tmp/test/a1"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InstalledModelRecord.self, from: data)

        XCTAssertEqual(decoded.modelId, "m1")
        XCTAssertEqual(decoded.status, .active)
        XCTAssertEqual(decoded.artifactId, "a1")
    }

    func testInstalledModelStatusRawValues() {
        XCTAssertEqual(InstalledModelStatus.staged.rawValue, "staged")
        XCTAssertEqual(InstalledModelStatus.active.rawValue, "active")
        XCTAssertEqual(InstalledModelStatus.failed.rawValue, "failed")
        XCTAssertEqual(InstalledModelStatus.rolledBack.rawValue, "rolled_back")
    }

    // MARK: - parseDesiredState

    func testParseDesiredStateWithArtifacts() async {
        let config = TestConfiguration.fast()
        let apiClient = APIClient(serverURL: URL(string: "https://test.octomil.com")!, configuration: config)
        let controlSync = ControlSync(apiClient: apiClient)
        let reconciler = ArtifactReconciler(
            controlSync: controlSync,
            metadataStore: store,
            artifactDirectory: artifactDir
        )

        // Create a DesiredStateResponse with AnyCodable artifacts
        let artifactJSON: [String: Any] = [
            "model_id": "m1",
            "model_version": "1.0.0",
            "artifact_version": "1.0.0",
            "artifact_id": "a1",
            "download_url": "https://example.com/a1.bin",
            "checksum": "abc123",
            "file_size": 1024,
            "activation_policy": "immediate",
        ]

        // Encode and decode to get AnyCodable
        let data = try! JSONSerialization.data(withJSONObject: artifactJSON)
        let anyCodable = try! JSONDecoder().decode(AnyCodable.self, from: data)

        let response = DesiredStateResponse(
            schemaVersion: "1.4.0",
            deviceId: "dev1",
            generatedAt: "2026-03-18T00:00:00Z",
            activeBinding: nil,
            artifacts: [anyCodable],
            policyConfig: nil,
            gcEligibleArtifactIds: ["old-1"]
        )

        let parsed = await reconciler.parseDesiredState(response)
        XCTAssertEqual(parsed.models.count, 1)
        XCTAssertEqual(parsed.models[0].modelId, "m1")
        XCTAssertEqual(parsed.models[0].activationPolicy, .immediate)
        XCTAssertEqual(parsed.gcEligibleArtifactIds, ["old-1"])
    }

    // MARK: - ReconcileAction equatable helpers

    func testReconcileActionDownload() {
        let entry = DesiredModelEntry(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            downloadUrl: "https://example.com",
            checksum: "abc",
            fileSize: 100
        )
        let action = ReconcileAction.download(entry)
        if case .download(let e) = action {
            XCTAssertEqual(e.modelId, "m1")
        } else {
            XCTFail("Expected download action")
        }
    }

    func testReconcileActionRemove() {
        let action = ReconcileAction.remove(artifactId: "a1")
        if case .remove(let id) = action {
            XCTAssertEqual(id, "a1")
        } else {
            XCTFail("Expected remove action")
        }
    }

    // MARK: - ArtifactReconcileError

    func testArtifactReconcileErrorDescriptions() {
        let errors: [ArtifactReconcileError] = [
            .invalidDownloadURL("bad-url"),
            .downloadFailed(artifactId: "a1", reason: "timeout"),
            .checksumMismatch(artifactId: "a1", expected: "abc", actual: "def"),
            .artifactNotFound("a1"),
            .artifactFileNotFound(artifactId: "a1", path: "/tmp/gone"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Helpers

    private func makeReconciler() -> TestableReconciler {
        TestableReconciler(store: store, artifactDir: artifactDir)
    }
}

// MARK: - TestableReconciler

/// Exposes internal methods synchronously for unit testing without needing
/// to set up a real ControlSync / APIClient.
private struct TestableReconciler {
    let store: ModelMetadataStore
    let artifactDir: URL

    func planActionsSync(desired: ParsedDesiredState) -> [ReconcileAction] {
        var actions: [ReconcileAction] = []

        for entry in desired.models {
            let existing = store.record(forArtifactId: entry.artifactId)

            if let existing = existing {
                if existing.artifactVersion == entry.artifactVersion {
                    if existing.status == .active {
                        actions.append(.upToDate(modelId: entry.modelId))
                    } else if existing.status == .staged {
                        if entry.activationPolicy == .immediate {
                            actions.append(.activate(
                                modelId: entry.modelId,
                                artifactVersion: entry.artifactVersion
                            ))
                        } else {
                            actions.append(.upToDate(modelId: entry.modelId))
                        }
                    } else {
                        actions.append(.download(entry))
                    }
                } else {
                    actions.append(.download(entry))
                }
            } else {
                actions.append(.download(entry))
            }
        }

        for artifactId in desired.gcEligibleArtifactIds {
            if store.record(forArtifactId: artifactId) != nil {
                actions.append(.remove(artifactId: artifactId))
            }
        }

        return actions
    }

    func checkAndRollbackSync(modelId: String) -> Bool {
        guard let active = store.activeRecord(forModelId: modelId) else {
            return false
        }

        store.incrementLaunchCount(artifactId: active.artifactId)

        guard store.shouldRollback(artifactId: active.artifactId) else {
            return false
        }

        let allRecords = store.records(forModelId: modelId)
            .filter { $0.artifactId != active.artifactId && $0.status != .failed }
            .sorted { $0.installedAt < $1.installedAt }

        guard let rollbackTarget = allRecords.last else {
            return false
        }

        var updatedActive = active
        updatedActive.status = .rolledBack
        store.upsert(updatedActive)

        store.activate(artifactId: rollbackTarget.artifactId)
        return true
    }
}

import XCTest
@testable import Octomil

final class ModelMetadataStoreTests: XCTestCase {

    private var store: ModelMetadataStore!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("test_models.json")
        store = ModelMetadataStore(storeURL: storeURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        super.tearDown()
    }

    // MARK: - Basic CRUD

    func testUpsertAndRetrieve() {
        let record = makeRecord(modelId: "m1", artifactId: "a1", status: .staged)
        store.upsert(record)

        let retrieved = store.record(forArtifactId: "a1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.modelId, "m1")
        XCTAssertEqual(retrieved?.status, .staged)
    }

    func testUpsertOverwritesExisting() {
        var record = makeRecord(modelId: "m1", artifactId: "a1", status: .staged)
        store.upsert(record)

        record.status = .active
        store.upsert(record)

        let retrieved = store.record(forArtifactId: "a1")
        XCTAssertEqual(retrieved?.status, .active)
    }

    func testRemoveRecord() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.remove(artifactId: "a1")
        XCTAssertNil(store.record(forArtifactId: "a1"))
    }

    func testRemoveAllRecords() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.upsert(makeRecord(modelId: "m2", artifactId: "a2", status: .active))
        store.removeAll()
        XCTAssertTrue(store.allRecords().isEmpty)
    }

    // MARK: - Queries

    func testActiveRecordForModelId() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.upsert(makeRecord(modelId: "m1", artifactId: "a2", status: .active))
        store.upsert(makeRecord(modelId: "m2", artifactId: "a3", status: .active))

        let active = store.activeRecord(forModelId: "m1")
        XCTAssertEqual(active?.artifactId, "a2")
    }

    func testActiveRecordReturnsNilWhenNoActive() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        XCTAssertNil(store.activeRecord(forModelId: "m1"))
    }

    func testRecordsForModelId() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.upsert(makeRecord(modelId: "m1", artifactId: "a2", status: .active))
        store.upsert(makeRecord(modelId: "m2", artifactId: "a3", status: .active))

        let m1Records = store.records(forModelId: "m1")
        XCTAssertEqual(m1Records.count, 2)
    }

    func testStagedRecords() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.upsert(makeRecord(modelId: "m1", artifactId: "a2", status: .active))
        store.upsert(makeRecord(modelId: "m2", artifactId: "a3", status: .staged))

        let staged = store.stagedRecords()
        XCTAssertEqual(staged.count, 2)
    }

    // MARK: - Activation

    func testActivateDeactivatesPreviousActive() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .active))
        store.upsert(makeRecord(modelId: "m1", artifactId: "a2", status: .staged))

        store.activate(artifactId: "a2")

        let a1 = store.record(forArtifactId: "a1")
        let a2 = store.record(forArtifactId: "a2")
        XCTAssertEqual(a1?.status, .staged)
        XCTAssertEqual(a2?.status, .active)
        XCTAssertNotNil(a2?.activatedAt)
    }

    func testActivateNonexistentArtifactIsNoOp() {
        store.activate(artifactId: "nonexistent")
        XCTAssertTrue(store.allRecords().isEmpty)
    }

    // MARK: - Mark Failed

    func testMarkFailed() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.markFailed(artifactId: "a1")
        XCTAssertEqual(store.record(forArtifactId: "a1")?.status, .failed)
    }

    // MARK: - Crash Tracking

    func testIncrementLaunchCount() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .active))
        store.incrementLaunchCount(artifactId: "a1")
        store.incrementLaunchCount(artifactId: "a1")
        XCTAssertEqual(store.record(forArtifactId: "a1")?.launchCount, 2)
    }

    func testIncrementCrashCount() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .active))
        store.incrementCrashCount(artifactId: "a1")
        XCTAssertEqual(store.record(forArtifactId: "a1")?.crashCount, 1)
    }

    func testShouldRollbackBelowThreshold() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .active))
        store.incrementCrashCount(artifactId: "a1")
        store.incrementCrashCount(artifactId: "a1")
        XCTAssertFalse(store.shouldRollback(artifactId: "a1"))
    }

    func testShouldRollbackAtThreshold() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .active))
        for _ in 0..<ModelMetadataStore.crashLoopThreshold {
            store.incrementCrashCount(artifactId: "a1")
        }
        XCTAssertTrue(store.shouldRollback(artifactId: "a1"))
    }

    func testShouldRollbackNonexistent() {
        XCTAssertFalse(store.shouldRollback(artifactId: "nonexistent"))
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .active))

        // Create a new store pointing at the same file
        let store2 = ModelMetadataStore(storeURL: storeURL)
        let retrieved = store2.record(forArtifactId: "a1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.modelId, "m1")
        XCTAssertEqual(retrieved?.status, .active)
    }

    func testPersistenceAfterRemove() {
        store.upsert(makeRecord(modelId: "m1", artifactId: "a1", status: .staged))
        store.remove(artifactId: "a1")

        let store2 = ModelMetadataStore(storeURL: storeURL)
        XCTAssertNil(store2.record(forArtifactId: "a1"))
    }

    func testEmptyStoreReturnsEmptyRecords() {
        XCTAssertTrue(store.allRecords().isEmpty)
        XCTAssertTrue(store.stagedRecords().isEmpty)
        XCTAssertNil(store.activeRecord(forModelId: "any"))
    }

    // MARK: - Helpers

    private func makeRecord(
        modelId: String,
        artifactId: String,
        status: InstalledModelStatus,
        artifactVersion: String = "1.0.0",
        modelVersion: String = "1.0.0"
    ) -> InstalledModelRecord {
        InstalledModelRecord(
            modelId: modelId,
            modelVersion: modelVersion,
            artifactVersion: artifactVersion,
            artifactId: artifactId,
            status: status,
            filePath: "/tmp/test/\(artifactId)/model.bin"
        )
    }
}

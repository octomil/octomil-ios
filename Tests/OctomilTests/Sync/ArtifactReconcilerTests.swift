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
        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                artifactManifest: ArtifactManifest(
                    artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 1024
                )
            ),
        ])

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
        // Create a real file so the existence check passes
        let filePath = tempDir.appendingPathComponent("a1").path
        FileManager.default.createFile(atPath: filePath, contents: Data())

        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: filePath
        ))

        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                artifactManifest: ArtifactManifest(
                    artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 1024
                )
            ),
        ])

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

        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "2.0.0",
                artifactManifest: ArtifactManifest(
                    artifactId: "a2", modelId: "m1", version: "2.0.0", totalBytes: 2048
                )
            ),
        ])

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .download(let entry) = actions[0] {
            XCTAssertEqual(entry.artifactManifest?.artifactId, "a2")
        } else {
            XCTFail("Expected download action for new version")
        }
    }

    func testPlanActionsStagedWithImmediatePolicy() {
        let filePath = tempDir.appendingPathComponent("a1").path
        FileManager.default.createFile(atPath: filePath, contents: Data())

        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .staged,
            filePath: filePath
        ))

        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                activationPolicy: "immediate",
                artifactManifest: ArtifactManifest(
                    artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 1024
                )
            ),
        ])

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
        let filePath = tempDir.appendingPathComponent("a1").path
        FileManager.default.createFile(atPath: filePath, contents: Data())

        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .staged,
            filePath: filePath
        ))

        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                activationPolicy: "next_launch",
                artifactManifest: ArtifactManifest(
                    artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 1024
                )
            ),
        ])

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

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

        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                artifactManifest: ArtifactManifest(
                    artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 1024
                )
            ),
        ])

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .download = actions[0] {
            // Re-download after failure
        } else {
            XCTFail("Expected download action for failed artifact")
        }
    }

    func testPlanActionsRedownloadWhenFilePurged() {
        // Record exists but file is gone from disk
        store.upsert(InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: "/tmp/nonexistent/a1"
        ))

        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                artifactManifest: ArtifactManifest(
                    artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 1024
                )
            ),
        ])

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)

        XCTAssertEqual(actions.count, 1)
        if case .download = actions[0] {
            // Re-download since file was purged
        } else {
            XCTFail("Expected download action for purged file")
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

        let desired = makeDesiredResponse(
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
        let desired = makeDesiredResponse(
            models: [],
            gcEligibleArtifactIds: ["nonexistent"]
        )

        let reconciler = makeReconciler()
        let actions = reconciler.planActionsSync(desired: desired)
        XCTAssertTrue(actions.isEmpty)
    }

    func testPlanActionsSkipsEntryWithoutArtifactManifest() {
        let desired = makeDesiredResponse(models: [
            DesiredModelEntry(
                modelId: "m1",
                desiredVersion: "1.0.0",
                artifactManifest: nil
            ),
        ])

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
        activeRecord.crashCount = ModelMetadataStore.crashLoopThreshold
        store.upsert(activeRecord)

        let reconciler = makeReconciler()
        let rolledBack = reconciler.checkAndRollbackSync(modelId: "m1")

        XCTAssertTrue(rolledBack)

        let active = store.activeRecord(forModelId: "m1")
        XCTAssertEqual(active?.artifactId, "a1-old")

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

    func testDesiredModelEntryDecoding() throws {
        let json = """
        {
            "modelId": "m1",
            "desiredVersion": "1.0.0",
            "deliveryMode": "managed",
            "activationPolicy": "immediate",
            "artifactManifest": {
                "artifactId": "a1",
                "modelId": "m1",
                "version": "1.0.0",
                "totalBytes": 1024
            }
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(DesiredModelEntry.self, from: json)
        XCTAssertEqual(entry.modelId, "m1")
        XCTAssertEqual(entry.desiredVersion, "1.0.0")
        XCTAssertEqual(entry.activationPolicy, "immediate")
        XCTAssertEqual(entry.artifactManifest?.artifactId, "a1")
        XCTAssertEqual(entry.artifactManifest?.totalBytes, 1024)
        XCTAssertNil(entry.rolloutId)
    }

    func testDesiredModelEntryDecodingWithNullOptionals() throws {
        let json = """
        {
            "modelId": "m1",
            "desiredVersion": "1.0.0",
            "deliveryMode": "managed",
            "activationPolicy": "next_launch",
            "enginePolicy": null,
            "artifactManifest": null,
            "rolloutId": null
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(DesiredModelEntry.self, from: json)
        XCTAssertEqual(entry.modelId, "m1")
        XCTAssertEqual(entry.activationPolicy, "next_launch")
        XCTAssertNil(entry.enginePolicy)
        XCTAssertNil(entry.artifactManifest)
    }

    func testDesiredStateResponseDecoding() throws {
        let json = """
        {
            "device_id": "dev1",
            "desired_state_version": 5,
            "models": [
                {
                    "modelId": "m1",
                    "desiredVersion": "1.0.0",
                    "deliveryMode": "managed",
                    "activationPolicy": "immediate",
                    "artifactManifest": {
                        "artifactId": "a1",
                        "modelId": "m1",
                        "version": "1.0.0",
                        "totalBytes": 1024
                    }
                }
            ],
            "gc_eligible_artifact_ids": ["old-1"]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DesiredStateResponse.self, from: json)
        XCTAssertEqual(response.deviceId, "dev1")
        XCTAssertEqual(response.desiredStateVersion, 5)
        XCTAssertEqual(response.models.count, 1)
        XCTAssertEqual(response.models[0].modelId, "m1")
        XCTAssertEqual(response.models[0].activationPolicy, "immediate")
        XCTAssertEqual(response.gcEligibleArtifactIds, ["old-1"])
    }

    func testEnginePolicyDecoding() throws {
        let json = """
        {
            "modelId": "m1",
            "desiredVersion": "1.0.0",
            "deliveryMode": "managed",
            "activationPolicy": "immediate",
            "enginePolicy": {
                "allowed": ["coreml", "llamacpp"],
                "forced": "coreml"
            }
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(DesiredModelEntry.self, from: json)
        XCTAssertEqual(entry.enginePolicy?.allowed, ["coreml", "llamacpp"])
        XCTAssertEqual(entry.enginePolicy?.forced, "coreml")
    }

    func testArtifactManifestResponseDecoding() throws {
        let json = """
        {
            "artifact_id": "a1",
            "model_id": "m1",
            "version": "1.0.0",
            "total_bytes": 2700000000,
            "files": [
                {"path": "model.bin", "size_bytes": 2600000000, "sha256": "abc123", "kind": "weights"},
                {"path": "tokenizer.json", "size_bytes": 100000000, "sha256": "def456", "kind": "tokenizer"}
            ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ArtifactManifestResponse.self, from: json)
        XCTAssertEqual(manifest.artifactId, "a1")
        XCTAssertEqual(manifest.files.count, 2)
        XCTAssertEqual(manifest.files[0].path, "model.bin")
        XCTAssertEqual(manifest.files[0].sha256, "abc123")
        XCTAssertEqual(manifest.files[0].kind, "weights")
        XCTAssertEqual(manifest.files[1].kind, "tokenizer")
        XCTAssertEqual(manifest.totalBytes, 2700000000)
    }

    func testArtifactManifestResponseDecodingWithoutKind() throws {
        let json = """
        {
            "artifact_id": "a1",
            "model_id": "m1",
            "version": "1.0.0",
            "total_bytes": 1024,
            "files": [
                {"path": "model.bin", "size_bytes": 1024, "sha256": "abc"}
            ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ArtifactManifestResponse.self, from: json)
        XCTAssertNil(manifest.files[0].kind)
    }

    func testDownloadUrlsResponseDecoding() throws {
        let json = """
        {
            "artifact_id": "a1",
            "urls": [
                {"path": "model.bin", "url": "https://cdn.example.com/model.bin?sig=abc"},
                {"path": "tokenizer.json", "url": "https://cdn.example.com/tokenizer.json?sig=def"}
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DownloadUrlsResponse.self, from: json)
        XCTAssertEqual(response.artifactId, "a1")
        XCTAssertEqual(response.urls.count, 2)
        XCTAssertEqual(response.urls[0].path, "model.bin")
    }

    func testObservedModelEntryCoding() throws {
        let entry = ObservedModelEntry(
            modelId: "m1",
            artifactId: "a1",
            artifactVersion: "1.0.0",
            status: "active",
            errorCode: nil
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ObservedModelEntry.self, from: data)
        XCTAssertEqual(decoded.modelId, "m1")
        XCTAssertEqual(decoded.artifactId, "a1")
        XCTAssertEqual(decoded.status, "active")
        XCTAssertNil(decoded.errorCode)
    }

    func testObservedModelEntryWithError() throws {
        let entry = ObservedModelEntry(
            modelId: "m1",
            artifactId: "a1",
            artifactVersion: "1.0.0",
            status: "failed",
            errorCode: "activation_failed"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ObservedModelEntry.self, from: data)
        XCTAssertEqual(decoded.errorCode, "activation_failed")
    }

    func testInstalledModelRecordCoding() throws {
        let record = InstalledModelRecord(
            modelId: "m1",
            modelVersion: "1.0.0",
            artifactVersion: "1.0.0",
            artifactId: "a1",
            status: .active,
            filePath: "/tmp/test/a1",
            resourceBindings: ["model.bin": "model.bin", "tokenizer.json": "tokenizer.json"]
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
        XCTAssertEqual(decoded.resourceBindings?["model.bin"], "model.bin")
    }

    func testInstalledModelRecordCodingWithoutResourceBindings() throws {
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

        XCTAssertNil(decoded.resourceBindings)
    }

    func testInstalledModelStatusRawValues() {
        XCTAssertEqual(InstalledModelStatus.staged.rawValue, "staged")
        XCTAssertEqual(InstalledModelStatus.active.rawValue, "active")
        XCTAssertEqual(InstalledModelStatus.failed.rawValue, "failed")
        XCTAssertEqual(InstalledModelStatus.rolledBack.rawValue, "rolled_back")
    }

    // MARK: - ReconcileAction

    func testReconcileActionDownload() {
        let entry = DesiredModelEntry(
            modelId: "m1",
            desiredVersion: "1.0.0",
            artifactManifest: ArtifactManifest(
                artifactId: "a1", modelId: "m1", version: "1.0.0", totalBytes: 100
            )
        )
        let action = ReconcileAction.download(entry)
        if case .download(let e) = action {
            XCTAssertEqual(e.modelId, "m1")
        } else {
            XCTFail("Expected download action")
        }
    }

    func testReconcileActionActivate() {
        let action = ReconcileAction.activate(modelId: "m1", version: "1.0.0")
        if case .activate(let modelId, let version) = action {
            XCTAssertEqual(modelId, "m1")
            XCTAssertEqual(version, "1.0.0")
        } else {
            XCTFail("Expected activate action")
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

    // MARK: - Resource Kind Inference

    func testInferResourceKindWeights() {
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "model.gguf"), "weights")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "model.bin"), "weights")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "phi-4.mlmodelc"), "weights")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "weights.safetensors"), "weights")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "model.tflite"), "weights")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "model.onnx"), "weights")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "model.mnn"), "weights")
    }

    func testInferResourceKindTokenizer() {
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "tokenizer.json"), "tokenizer")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "tokenizer.model"), "tokenizer")
    }

    func testInferResourceKindConfig() {
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "config.json"), "model_config")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "tokenizer_config.json"), "tokenizer_config")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "generation_config.json"), "generation_config")
    }

    func testInferResourceKindVocabAndMerges() {
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "vocab.json"), "vocab")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "vocab.txt"), "vocab")
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "merges.txt"), "merges")
    }

    func testInferResourceKindFallback() {
        // Unknown extension falls back to filename stem
        XCTAssertEqual(ArtifactReconciler.inferResourceKind(from: "custom_data.xyz"), "custom_data")
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

    private func makeDesiredResponse(
        models: [DesiredModelEntry],
        gcEligibleArtifactIds: [String] = []
    ) -> DesiredStateResponse {
        DesiredStateResponse(
            deviceId: "dev1",
            desiredStateVersion: 1,
            models: models,
            gcEligibleArtifactIds: gcEligibleArtifactIds
        )
    }
}

// MARK: - TestableReconciler

/// Mirrors the planActions logic from ArtifactReconciler for synchronous
/// unit testing without needing a real ControlSync / APIClient.
private struct TestableReconciler {
    let store: ModelMetadataStore
    let artifactDir: URL

    func planActionsSync(desired: DesiredStateResponse) -> [ReconcileAction] {
        var actions: [ReconcileAction] = []

        for entry in desired.models {
            let artifactId = entry.artifactManifest?.artifactId ?? ""
            guard !artifactId.isEmpty else { continue }

            let existing = store.record(forArtifactId: artifactId)

            if let existing = existing {
                if existing.artifactVersion == entry.desiredVersion {
                    // Re-download if files were purged from disk
                    let pathExists = FileManager.default.fileExists(atPath: existing.filePath)
                    if !pathExists {
                        actions.append(.download(entry))
                    } else if existing.status == .active {
                        actions.append(.upToDate(modelId: entry.modelId))
                    } else if existing.status == .staged {
                        if entry.activationPolicy == "immediate" {
                            actions.append(.activate(
                                modelId: entry.modelId,
                                version: entry.desiredVersion
                            ))
                        } else {
                            actions.append(.upToDate(modelId: entry.modelId))
                        }
                    } else {
                        // Failed or rolled-back — re-download
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

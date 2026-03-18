import XCTest
@testable import Octomil

final class BenchmarkStoreTests: XCTestCase {

    private var store: BenchmarkStore!
    private var testDefaults: UserDefaults!
    private let suiteName = "test_benchmark_store"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        store = BenchmarkStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Store and retrieve

    func testRecordAndRetrieveWinner() {
        let url = URL(fileURLWithPath: "/tmp/models/whisper-tiny.bin")
        store.record(winner: .whisper, modelId: "whisper-tiny", modelURL: url)

        let result = store.winner(modelId: "whisper-tiny", modelURL: url)
        XCTAssertEqual(result, .whisper)
    }

    func testWinnerReturnsNilWhenNotRecorded() {
        let url = URL(fileURLWithPath: "/tmp/models/llama.gguf")
        let result = store.winner(modelId: "llama-3.2", modelURL: url)
        XCTAssertNil(result)
    }

    // MARK: - Clear

    func testClearAllRemovesAllBenchmarks() {
        let url1 = URL(fileURLWithPath: "/tmp/models/model-a.bin")
        let url2 = URL(fileURLWithPath: "/tmp/models/model-b.bin")

        store.record(winner: .llamaCpp, modelId: "model-a", modelURL: url1)
        store.record(winner: .coreml, modelId: "model-b", modelURL: url2)

        XCTAssertNotNil(store.winner(modelId: "model-a", modelURL: url1))
        XCTAssertNotNil(store.winner(modelId: "model-b", modelURL: url2))

        store.clearAll()

        XCTAssertNil(store.winner(modelId: "model-a", modelURL: url1))
        XCTAssertNil(store.winner(modelId: "model-b", modelURL: url2))
    }

    // MARK: - Independent models

    func testDifferentModelsStoreIndependentWinners() {
        let url1 = URL(fileURLWithPath: "/tmp/models/model-a.gguf")
        let url2 = URL(fileURLWithPath: "/tmp/models/model-b.gguf")

        store.record(winner: .llamaCpp, modelId: "model-a", modelURL: url1)
        store.record(winner: .coreml, modelId: "model-b", modelURL: url2)

        XCTAssertEqual(store.winner(modelId: "model-a", modelURL: url1), .llamaCpp)
        XCTAssertEqual(store.winner(modelId: "model-b", modelURL: url2), .coreml)
    }

    // MARK: - Key identity hierarchy

    func testDigestKeyTakesPrecedence() {
        let url = URL(fileURLWithPath: "/tmp/models/model.bin")
        let digest = "abc123def456"

        store.record(winner: .mlx, modelId: "model", modelURL: url, artifactDigest: digest)
        let result = store.winner(modelId: "model", modelURL: url, artifactDigest: digest)
        XCTAssertEqual(result, .mlx)

        // Without digest, should NOT find the same record
        let noDigest = store.winner(modelId: "model", modelURL: url)
        XCTAssertNil(noDigest, "Digest-keyed record should not match path-keyed lookup")
    }

    func testModelVersionKeyUsedWhenNoDigest() {
        let url = URL(fileURLWithPath: "/tmp/models/model.bin")

        store.record(winner: .coreml, modelId: "model", modelURL: url, modelVersion: "1.2.0")
        let result = store.winner(modelId: "model", modelURL: url, modelVersion: "1.2.0")
        XCTAssertEqual(result, .coreml)

        // Different version should NOT match
        let otherVersion = store.winner(modelId: "model", modelURL: url, modelVersion: "2.0.0")
        XCTAssertNil(otherVersion)
    }

    func testPathSizeFallbackWhenNoVersionOrDigest() {
        let url = URL(fileURLWithPath: "/tmp/models/model.bin")

        store.record(winner: .llamaCpp, modelId: "model", modelURL: url)
        let result = store.winner(modelId: "model", modelURL: url)
        XCTAssertEqual(result, .llamaCpp)
    }

    // MARK: - Key includes artifact path

    func testDifferentPathsProduceDifferentKeys() {
        let url1 = URL(fileURLWithPath: "/tmp/v1/model.bin")
        let url2 = URL(fileURLWithPath: "/tmp/v2/model.bin")

        let key1 = store.storeKey(modelId: "model", modelURL: url1)
        let key2 = store.storeKey(modelId: "model", modelURL: url2)

        XCTAssertNotEqual(key1, key2, "Different artifact paths should produce different keys")
    }

    // MARK: - Canonical artifact path

    func testCanonicalArtifactPath_extractsLastTwoComponents() {
        let url = URL(fileURLWithPath: "/Users/sean/models/whisper/tiny.bin")
        let path = BenchmarkStore.canonicalArtifactPath(url)
        XCTAssertEqual(path, "whisper/tiny.bin")
    }

    func testCanonicalArtifactPath_singleComponent() {
        let url = URL(fileURLWithPath: "/model.bin")
        let path = BenchmarkStore.canonicalArtifactPath(url)
        XCTAssertTrue(path.hasSuffix("model.bin"))
    }

    // MARK: - Key format

    func testStoreKeyContainsPrefix() {
        let url = URL(fileURLWithPath: "/tmp/models/whisper-tiny.bin")
        let key = store.storeKey(modelId: "whisper-tiny", modelURL: url)
        XCTAssertTrue(key.hasPrefix("octomil_bm_"))
    }

    func testStoreKeyWithDigestContainsDigestPrefix() {
        let url = URL(fileURLWithPath: "/tmp/models/model.bin")
        let key = store.storeKey(modelId: "model", modelURL: url, artifactDigest: "deadbeef")
        XCTAssertTrue(key.contains("d:deadbeef"), "Key should contain digest prefix")
    }

    func testStoreKeyWithVersionContainsVersionPrefix() {
        let url = URL(fileURLWithPath: "/tmp/models/model.bin")
        let key = store.storeKey(modelId: "model", modelURL: url, modelVersion: "1.0.0")
        XCTAssertTrue(key.contains("v:1.0.0"), "Key should contain version prefix")
    }

    func testStoreKeyWithPathFallbackContainsPathPrefix() {
        let url = URL(fileURLWithPath: "/tmp/models/model.bin")
        let key = store.storeKey(modelId: "model", modelURL: url)
        XCTAssertTrue(key.contains("p:"), "Key should contain path prefix")
        XCTAssertTrue(key.contains("s:"), "Key should contain size prefix")
    }

    // MARK: - All Engine types roundtrip

    func testAllEngineTypesRoundtrip() {
        let engines: [Engine] = [.auto, .coreml, .mlx, .llamaCpp, .sherpa, .whisper]
        let url = URL(fileURLWithPath: "/tmp/model.bin")

        for engine in engines {
            store.record(winner: engine, modelId: "test-\(engine.rawValue)", modelURL: url)
            let result = store.winner(modelId: "test-\(engine.rawValue)", modelURL: url)
            XCTAssertEqual(result, engine, "Engine \(engine.rawValue) should roundtrip")
        }
    }
}

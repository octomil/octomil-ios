import XCTest

@testable import Octomil

final class PrepareManagerTests: XCTestCase {
    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-pm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testCanPrepareReturnsTrueForWellFormedCandidate() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let candidate = makeCandidate()
        XCTAssertTrue(pm.canPrepare(candidate))
    }

    func testCanPrepareReturnsFalseForSyntheticCandidate() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let candidate = makeCandidate(downloadUrls: [])
        XCTAssertFalse(pm.canPrepare(candidate))
    }

    func testArtifactDirForMatchesPython() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let dir = try pm.artifactDirFor("kokoro-82m")
        // Cross-SDK conformance.
        XCTAssertEqual(dir.lastPathComponent, "kokoro-82m-64e5b12f9efb")
    }

    func testArtifactDirForRejectsEmptyId() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        XCTAssertThrowsError(try pm.artifactDirFor(""))
    }

    func testValidatesLocalityAndDeliveryMode() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let cloud = makeCandidate(locality: "cloud")
        XCTAssertFalse(pm.canPrepare(cloud))

        let hostedGateway = makeCandidate(deliveryMode: "hosted_gateway")
        XCTAssertFalse(pm.canPrepare(hostedGateway))
    }

    func testDisabledPolicyRejected() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let candidate = makeCandidate(preparePolicy: .disabled)
        XCTAssertFalse(pm.canPrepare(candidate))
    }

    func testStaticRecipeRegistryHasKokoro() {
        XCTAssertNotNil(StaticRecipeRegistry.shared.recipe(for: "kokoro-82m"))
        XCTAssertNotNil(StaticRecipeRegistry.shared.recipe(for: "kokoro-en-v0_19"))
    }

    func testStaticRecipeKokoroDigestMatchesPython() {
        let recipe = StaticRecipeRegistry.shared.recipe(for: "kokoro-82m")
        XCTAssertEqual(
            recipe?.file.digest,
            "sha256:912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7"
        )
    }

    // MARK: - helpers

    private func makeCandidate(
        locality: String = "local",
        deliveryMode: String = "sdk_runtime",
        preparePolicy: PreparePolicy = .lazy,
        prepareRequired: Bool = true,
        downloadUrls: [ArtifactDownloadEndpoint]? = nil
    ) -> PrepareCandidate {
        let urls =
            downloadUrls
            ?? [ArtifactDownloadEndpoint(url: URL(string: "https://cdn.example.com/")!)]
        let artifact = PrepareArtifactPlan(
            modelId: "kokoro-82m",
            artifactId: "kokoro-82m",
            digest: "sha256:" + String(repeating: "0", count: 64),
            requiredFiles: [],
            downloadUrls: urls
        )
        return PrepareCandidate(
            locality: locality,
            engine: "sherpa-onnx",
            artifact: artifact,
            deliveryMode: deliveryMode,
            prepareRequired: prepareRequired,
            preparePolicy: preparePolicy
        )
    }
}

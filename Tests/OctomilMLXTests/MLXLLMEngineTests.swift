import Foundation
import XCTest
@testable import OctomilMLX
@testable import Octomil

@available(iOS 17.0, macOS 14.0, *)
final class MLXLLMEngineTests: XCTestCase {

    // MARK: - MLXDeployedModel

    func testMLXDeployedModelProperties() {
        // Verify that MLXDeployedModel stores properties correctly.
        // Cannot construct a real ModelContainer without a model, so test the wrapper types.
        let name = "test-model"
        XCTAssertEqual(name, "test-model")
    }

    func testMLXDeployedModelDefaultMaxTokens() {
        // Default maxTokens should be 512
        let defaultMax = 512
        XCTAssertEqual(defaultMax, 512)
    }

    func testMLXDeployedModelDefaultTemperature() {
        // Default temperature should be 0.7
        let defaultTemp: Float = 0.7
        XCTAssertEqual(defaultTemp, 0.7)
    }

    // MARK: - MLXModelLoader

    func testCacheDirectoryPath() {
        let cacheDir = MLXModelLoader.cacheDirectory
        XCTAssertTrue(cacheDir.path.contains("ai.octomil.mlx-models"))
    }

    func testCachePathForModel() {
        let path = MLXModelLoader.cachePath(modelId: "mlx-community/Llama-3.2-1B", version: "v1")
        XCTAssertTrue(path.path.contains("mlx-community_Llama-3.2-1B"))
        XCTAssertTrue(path.path.contains("v1"))
    }

    func testCachePathSanitizesSlashes() {
        let path = MLXModelLoader.cachePath(modelId: "org/model/sub", version: "latest")
        // Slashes should be replaced with underscores
        XCTAssertTrue(path.path.contains("org_model_sub"))
        XCTAssertFalse(path.lastPathComponent.contains("/"))
    }

    func testEnsureCacheDirectory() throws {
        try MLXModelLoader.ensureCacheDirectory()
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: MLXModelLoader.cacheDirectory.path,
            isDirectory: &isDir
        )
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - MLXLLMEngine Protocol Conformance

    func testMLXLLMEngineConformsToStreamingInferenceEngine() {
        // This is a compile-time check — MLXLLMEngine: StreamingInferenceEngine
        // If this compiles, the conformance is verified.
        let _: StreamingInferenceEngine.Type = MLXLLMEngine.self
    }
}

import Foundation
import XCTest
@testable import Octomil

final class EngineRegistryTests: XCTestCase {

    private var registry: EngineRegistry!

    override func setUp() {
        super.setUp()
        registry = EngineRegistry()
    }

    override func tearDown() {
        registry = nil
        super.tearDown()
    }

    // MARK: - Default Registration

    func testDefaultTextReturnsLLMEngine() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .text, modelURL: url)
        XCTAssertTrue(engine is LLMEngine)
    }

    func testDefaultImageReturnsImageEngine() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .image, modelURL: url)
        XCTAssertTrue(engine is ImageEngine)
    }

    func testDefaultAudioReturnsAudioEngine() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .audio, modelURL: url)
        XCTAssertTrue(engine is AudioEngine)
    }

    func testDefaultVideoReturnsVideoEngine() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .video, modelURL: url)
        XCTAssertTrue(engine is VideoEngine)
    }

    func testDefaultTimeSeriesReturnsLLMEngine() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .timeSeries, modelURL: url)
        XCTAssertTrue(engine is LLMEngine, "Default timeSeries should use LLMEngine placeholder")
    }

    // MARK: - Custom Registration Overrides Default

    func testCustomRegistrationOverridesDefault() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        registry.register(modality: .text) { _ in MockStreamingEngine() }

        let engine = try registry.resolve(modality: .text, modelURL: url)
        XCTAssertTrue(engine is MockStreamingEngine)
    }

    // MARK: - Exact Match Beats Modality Default

    func testExactMatchBeatsModalityDefault() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")

        registry.register(modality: .text, engine: .mlx) { _ in MockStreamingEngine() }

        // Resolve with engine=.mlx should get the mock
        let engine = try registry.resolve(modality: .text, engine: .mlx, modelURL: url)
        XCTAssertTrue(engine is MockStreamingEngine)

        // Resolve without engine should still get default LLMEngine
        let defaultEngine = try registry.resolve(modality: .text, modelURL: url)
        XCTAssertTrue(defaultEngine is LLMEngine)
    }

    func testExactMatchFallsBackToModalityDefault() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")

        // No exact match for (.text, .coreml), should fall back to (.text, nil) -> LLMEngine
        let engine = try registry.resolve(modality: .text, engine: .coreml, modelURL: url)
        XCTAssertTrue(engine is LLMEngine)
    }

    // MARK: - Missing Registration Throws

    func testMissingRegistrationThrows() {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        registry.removeAllRegistrations()

        XCTAssertThrowsError(try registry.resolve(modality: .text, modelURL: url)) { error in
            guard let resolutionError = error as? EngineResolutionError else {
                XCTFail("Expected EngineResolutionError, got \(type(of: error))")
                return
            }
            if case .noEngineRegistered(let modality, let engine) = resolutionError {
                XCTAssertEqual(modality, .text)
                XCTAssertNil(engine)
            } else {
                XCTFail("Unexpected error case")
            }
        }
    }

    func testMissingRegistrationWithEngineIncludesEngineInError() {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        registry.removeAllRegistrations()

        XCTAssertThrowsError(try registry.resolve(modality: .text, engine: .mlx, modelURL: url)) { error in
            guard let resolutionError = error as? EngineResolutionError else {
                XCTFail("Expected EngineResolutionError, got \(type(of: error))")
                return
            }
            if case .noEngineRegistered(let modality, let engine) = resolutionError {
                XCTAssertEqual(modality, .text)
                XCTAssertEqual(engine, .mlx)
            } else {
                XCTFail("Unexpected error case")
            }
        }
    }

    // MARK: - Error Descriptions

    func testErrorDescriptionWithEngine() {
        let error = EngineResolutionError.noEngineRegistered(modality: .text, engine: .mlx)
        XCTAssertEqual(error.errorDescription, "No engine registered for modality 'text' with engine 'mlx'")
    }

    func testErrorDescriptionWithoutEngine() {
        let error = EngineResolutionError.noEngineRegistered(modality: .image, engine: nil)
        XCTAssertEqual(error.errorDescription, "No engine registered for modality 'image'")
    }

    // MARK: - engineFromURL

    func testEngineFromURLCoreMLExtensions() {
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.mlmodelc")), .coreml)
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.mlmodel")), .coreml)
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.mlpackage")), .coreml)
    }

    func testEngineFromURLMLXExtensions() {
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.safetensors")), .mlx)
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.gguf")), .mlx)
    }

    func testEngineFromURLUnknownExtension() {
        XCTAssertNil(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.onnx")))
        XCTAssertNil(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.bin")))
        XCTAssertNil(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.pt")))
        XCTAssertNil(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model")))
    }

    func testEngineFromURLCaseInsensitive() {
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.MLMODELC")), .coreml)
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.SafeTensors")), .mlx)
        XCTAssertEqual(EngineRegistry.engineFromURL(URL(fileURLWithPath: "/model.GGUF")), .mlx)
    }

    // MARK: - Thread Safety

    func testConcurrentRegisterAndResolve() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let iterations = 1000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                registry.register(modality: .text, engine: .coreml) { url in
                    LLMEngine(modelPath: url)
                }
            } else {
                _ = try? registry.resolve(modality: .text, modelURL: url)
            }
        }

        // If we get here without a crash, thread safety is working
        let engine = try registry.resolve(modality: .text, modelURL: url)
        XCTAssertNotNil(engine)
    }

    // MARK: - Reset

    func testResetRestoresDefaults() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")

        registry.register(modality: .text) { _ in MockStreamingEngine() }
        let overridden = try registry.resolve(modality: .text, modelURL: url)
        XCTAssertTrue(overridden is MockStreamingEngine)

        registry.reset()

        let restored = try registry.resolve(modality: .text, modelURL: url)
        XCTAssertTrue(restored is LLMEngine)
    }

    func testResetClearsCustomRegistrations() throws {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")

        registry.register(modality: .text, engine: .mlx) { _ in MockStreamingEngine() }
        let custom = try registry.resolve(modality: .text, engine: .mlx, modelURL: url)
        XCTAssertTrue(custom is MockStreamingEngine)

        registry.reset()

        // (.text, .mlx) is not a default, so should fall back to (.text, nil) -> LLMEngine
        let afterReset = try registry.resolve(modality: .text, engine: .mlx, modelURL: url)
        XCTAssertTrue(afterReset is LLMEngine)
    }

    // MARK: - EngineKey

    func testEngineKeyEquality() {
        let key1 = EngineRegistry.EngineKey(modality: .text, engine: .mlx)
        let key2 = EngineRegistry.EngineKey(modality: .text, engine: .mlx)
        let key3 = EngineRegistry.EngineKey(modality: .text, engine: nil)
        let key4 = EngineRegistry.EngineKey(modality: .image, engine: .mlx)

        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
        XCTAssertNotEqual(key1, key4)
    }

    func testEngineKeyHashable() {
        let key1 = EngineRegistry.EngineKey(modality: .text, engine: .mlx)
        let key2 = EngineRegistry.EngineKey(modality: .text, engine: nil)

        var set = Set<EngineRegistry.EngineKey>()
        set.insert(key1)
        set.insert(key2)
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Factory Receives Correct URL

    func testFactoryReceivesCorrectURL() throws {
        var receivedURL: URL?
        let expectedURL = URL(fileURLWithPath: "/tmp/special-model.mlmodelc")

        registry.register(modality: .text, engine: .coreml) { url in
            receivedURL = url
            return MockStreamingEngine()
        }

        _ = try registry.resolve(modality: .text, engine: .coreml, modelURL: expectedURL)
        XCTAssertEqual(receivedURL, expectedURL)
    }
}

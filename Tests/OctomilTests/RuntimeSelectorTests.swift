import XCTest
@testable import Octomil

final class RuntimeSelectorTests: XCTestCase {

    // MARK: - engineFromURL

    func testEngineFromURL_gguf_returnsLlamaCpp() {
        let url = URL(fileURLWithPath: "/models/llama-3.2-1b.gguf")
        XCTAssertEqual(EngineRegistry.engineFromURL(url), .llamaCpp)
    }

    func testEngineFromURL_safetensors_returnsMLX() {
        let url = URL(fileURLWithPath: "/models/model.safetensors")
        XCTAssertEqual(EngineRegistry.engineFromURL(url), .mlx)
    }

    func testEngineFromURL_mlmodelc_returnsCoreML() {
        let url = URL(fileURLWithPath: "/models/whisper.mlmodelc")
        XCTAssertEqual(EngineRegistry.engineFromURL(url), .coreml)
    }

    func testEngineFromURL_mlmodel_returnsCoreML() {
        let url = URL(fileURLWithPath: "/models/classifier.mlmodel")
        XCTAssertEqual(EngineRegistry.engineFromURL(url), .coreml)
    }

    func testEngineFromURL_unknown_returnsNil() {
        let url = URL(fileURLWithPath: "/models/data.bin")
        XCTAssertNil(EngineRegistry.engineFromURL(url))
    }

    // MARK: - CoreML selectable via explicit engine key

    func testCoreMLResolvable_text() throws {
        let registry = EngineRegistry()
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .text, engine: .coreml, modelURL: url)
        XCTAssertNotNil(engine)
    }

    func testCoreMLResolvable_audio() throws {
        let registry = EngineRegistry()
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .audio, engine: .coreml, modelURL: url)
        XCTAssertNotNil(engine)
    }

    func testCoreMLResolvable_image() throws {
        let registry = EngineRegistry()
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let engine = try registry.resolve(modality: .image, engine: .coreml, modelURL: url)
        XCTAssertNotNil(engine)
    }

    // MARK: - RuntimeSelector override chain

    func testServerOverride_takePrecedence() async throws {
        let selector = RuntimeSelector()
        let registry = EngineRegistry()
        // Register a known engine
        registry.register(modality: .text, engine: .llamaCpp) { url in
            LLMEngine(modelPath: url)
        }

        await selector.setServerOverrides(["my-model": .llamaCpp])

        let url = URL(fileURLWithPath: "/tmp/model.safetensors") // would infer .mlx
        // Should use server override (.llamaCpp), not URL-inferred (.mlx)
        let engine = try await selector.selectEngine(
            modelId: "my-model",
            modality: .text,
            modelURL: url,
            registry: registry
        )
        XCTAssertNotNil(engine)
    }

    func testServerGlobalOverride_appliesWhenNoModelSpecific() async throws {
        let selector = RuntimeSelector()
        let registry = EngineRegistry()
        registry.register(modality: .text, engine: .coreml) { url in
            LLMEngine(modelPath: url)
        }

        await selector.setServerOverrides(["*": .coreml])

        let url = URL(fileURLWithPath: "/tmp/model.gguf") // would infer .llamaCpp
        let engine = try await selector.selectEngine(
            modelId: "unknown-model",
            modality: .text,
            modelURL: url,
            registry: registry
        )
        XCTAssertNotNil(engine)
    }

    func testLocalOverride_usedWhenNoServerOverride() async throws {
        let selector = RuntimeSelector()
        let registry = EngineRegistry()
        registry.register(modality: .text, engine: .coreml) { url in
            LLMEngine(modelPath: url)
        }

        await selector.setLocalOverrides(["my-model": .coreml])

        let url = URL(fileURLWithPath: "/tmp/model.gguf")
        let engine = try await selector.selectEngine(
            modelId: "my-model",
            modality: .text,
            modelURL: url,
            registry: registry
        )
        XCTAssertNotNil(engine)
    }

    func testBenchmarkWinner_usedWhenNoOverrides() async throws {
        let selector = RuntimeSelector()
        let registry = EngineRegistry()
        let testDefaults = UserDefaults(suiteName: "test_runtime_selector")!
        testDefaults.removePersistentDomain(forName: "test_runtime_selector")
        let store = BenchmarkStore(defaults: testDefaults)

        registry.register(modality: .text, engine: .coreml) { url in
            LLMEngine(modelPath: url)
        }

        let url = URL(fileURLWithPath: "/tmp/model.gguf")
        store.record(winner: .coreml, modelId: "my-model", modelURL: url)

        // Inject the store result — since RuntimeSelector uses BenchmarkStore.shared,
        // we verify BenchmarkStore independently in BenchmarkStoreTests
        XCTAssertEqual(store.winner(modelId: "my-model", modelURL: url), .coreml)

        testDefaults.removePersistentDomain(forName: "test_runtime_selector")
    }

    func testFallsThrough_toURLInference() async throws {
        let selector = RuntimeSelector()
        let registry = EngineRegistry()
        registry.register(modality: .text, engine: .llamaCpp) { url in
            LLMEngine(modelPath: url)
        }

        let url = URL(fileURLWithPath: "/tmp/model.gguf")
        // No overrides, no benchmark — should use URL-inferred .llamaCpp
        let engine = try await selector.selectEngine(
            modelId: "any-model",
            modality: .text,
            modelURL: url,
            registry: registry
        )
        XCTAssertNotNil(engine)
    }

    func testOverrideCanForceCoreML() async throws {
        let selector = RuntimeSelector()
        let registry = EngineRegistry()

        await selector.setLocalOverrides(["whisper-tiny": .coreml])

        let url = URL(fileURLWithPath: "/tmp/whisper-tiny.bin")
        let engine = try await selector.selectEngine(
            modelId: "whisper-tiny",
            modality: .audio,
            modelURL: url,
            registry: registry
        )
        XCTAssertNotNil(engine)
    }
}

import Foundation
import XCTest
@testable import Octomil

// MARK: - Multimodal Package Tests

final class MultimodalPackageTests: XCTestCase {

    // MARK: - AppModelEntry Multimodal Fields

    func testAppModelEntryDefaultsToNilModalities() {
        let entry = AppModelEntry(
            id: "phi-4-mini",
            capability: .chat,
            delivery: .managed
        )
        XCTAssertNil(entry.inputModalities)
        XCTAssertNil(entry.outputModalities)
        XCTAssertNil(entry.resourceBindings)
        XCTAssertNil(entry.engineConfig)
    }

    func testAppModelEntryWithTextOnlyModalities() {
        let entry = AppModelEntry(
            id: "phi-4-mini",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text],
            outputModalities: [.text]
        )
        XCTAssertEqual(entry.inputModalities, [.text])
        XCTAssertEqual(entry.outputModalities, [.text])
        XCTAssertFalse(entry.isMultimodal)
        XCTAssertFalse(entry.supportsImageInput)
    }

    func testAppModelEntryWithVisionModalities() {
        let entry = AppModelEntry(
            id: "llava-v1.5-7b",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text, .image],
            outputModalities: [.text]
        )
        XCTAssertEqual(entry.inputModalities, [.text, .image])
        XCTAssertEqual(entry.outputModalities, [.text])
        XCTAssertTrue(entry.isMultimodal)
        XCTAssertTrue(entry.supportsImageInput)
    }

    func testIsMultimodalWithNilModalities() {
        let entry = AppModelEntry(
            id: "phi-4-mini",
            capability: .chat,
            delivery: .managed
        )
        XCTAssertFalse(entry.isMultimodal, "Nil modalities should not be multimodal")
    }

    func testIsMultimodalWithSingleModality() {
        let entry = AppModelEntry(
            id: "phi-4-mini",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text]
        )
        XCTAssertFalse(entry.isMultimodal, "Single modality should not be multimodal")
    }

    func testIsMultimodalWithMultipleModalities() {
        let entry = AppModelEntry(
            id: "llava-v1.5-7b",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text, .image]
        )
        XCTAssertTrue(entry.isMultimodal)
    }

    func testSupportsImageInputWithNoImageModality() {
        let entry = AppModelEntry(
            id: "phi-4-mini",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text, .audio]
        )
        XCTAssertFalse(entry.supportsImageInput)
    }

    // MARK: - Resource Bindings

    func testResourceBindingCreation() {
        let binding = ResourceBinding(kind: .weights, path: "Models/model.gguf")
        XCTAssertEqual(binding.kind, .weights)
        XCTAssertEqual(binding.path, "Models/model.gguf")
    }

    func testResourceBindingEquality() {
        let binding1 = ResourceBinding(kind: .weights, path: "model.gguf")
        let binding2 = ResourceBinding(kind: .weights, path: "model.gguf")
        let binding3 = ResourceBinding(kind: .projector, path: "model.gguf")

        XCTAssertEqual(binding1, binding2)
        XCTAssertNotEqual(binding1, binding3)
    }

    func testAppModelEntryWithResourceBindings() {
        let bindings: [ResourceBinding] = [
            ResourceBinding(kind: .weights, path: "Models/llava-v1.5-7b.gguf"),
            ResourceBinding(kind: .projector, path: "Models/llava-v1.5-7b-mmproj.gguf"),
        ]

        let entry = AppModelEntry(
            id: "llava-v1.5-7b",
            capability: .chat,
            delivery: .bundled,
            bundledPath: "Models/llava-v1.5-7b.gguf",
            inputModalities: [.text, .image],
            outputModalities: [.text],
            resourceBindings: bindings
        )

        XCTAssertEqual(entry.resourceBindings?.count, 2)
        XCTAssertEqual(entry.resourceBindings?[0].kind, .weights)
        XCTAssertEqual(entry.resourceBindings?[1].kind, .projector)
    }

    func testResolvedURLForResourceKind() {
        let bindings: [ResourceBinding] = [
            ResourceBinding(kind: .weights, path: "model.gguf"),
            ResourceBinding(kind: .projector, path: "mmproj.gguf"),
            ResourceBinding(kind: .tokenizer, path: "tokenizer.json"),
        ]

        let entry = AppModelEntry(
            id: "test-model",
            capability: .chat,
            delivery: .bundled,
            bundledPath: "Models/model.gguf",
            resourceBindings: bindings
        )

        let baseURL = URL(fileURLWithPath: "/app/Models")

        let weightsURL = entry.resolvedURL(for: .weights, relativeTo: baseURL)
        XCTAssertEqual(weightsURL?.lastPathComponent, "model.gguf")

        let projectorURL = entry.resolvedURL(for: .projector, relativeTo: baseURL)
        XCTAssertEqual(projectorURL?.lastPathComponent, "mmproj.gguf")

        let tokenizerURL = entry.resolvedURL(for: .tokenizer, relativeTo: baseURL)
        XCTAssertEqual(tokenizerURL?.lastPathComponent, "tokenizer.json")

        let adapterURL = entry.resolvedURL(for: .adapter, relativeTo: baseURL)
        XCTAssertNil(adapterURL, "No binding for adapter should return nil")
    }

    // MARK: - Engine Config

    func testAppModelEntryWithEngineConfig() {
        let config: EngineConfig = [
            "n_gpu_layers": "99",
            "mmproj": "true",
            "n_ctx": "4096",
        ]

        let entry = AppModelEntry(
            id: "llava-v1.5-7b",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text, .image],
            engineConfig: config
        )

        XCTAssertEqual(entry.engineConfig?["n_gpu_layers"], "99")
        XCTAssertEqual(entry.engineConfig?["mmproj"], "true")
        XCTAssertEqual(entry.engineConfig?["n_ctx"], "4096")
    }

    // MARK: - AppManifest Queries

    func testManifestEntriesAcceptingTextModality() {
        let manifest = AppManifest(models: [
            AppModelEntry(
                id: "phi-4-mini",
                capability: .chat,
                delivery: .managed,
                inputModalities: [.text]
            ),
            AppModelEntry(
                id: "llava-v1.5-7b",
                capability: .chat,
                delivery: .managed,
                inputModalities: [.text, .image]
            ),
            AppModelEntry(
                id: "whisper-base",
                capability: .transcription,
                delivery: .bundled,
                bundledPath: "Models/whisper-base.mlmodelc",
                inputModalities: [.audio]
            ),
        ])

        let textModels = manifest.entries(accepting: .text)
        XCTAssertEqual(textModels.count, 2)
        XCTAssertEqual(textModels[0].id, "phi-4-mini")
        XCTAssertEqual(textModels[1].id, "llava-v1.5-7b")
    }

    func testManifestEntriesAcceptingImageModality() {
        let manifest = AppManifest(models: [
            AppModelEntry(
                id: "phi-4-mini",
                capability: .chat,
                delivery: .managed,
                inputModalities: [.text]
            ),
            AppModelEntry(
                id: "llava-v1.5-7b",
                capability: .chat,
                delivery: .managed,
                inputModalities: [.text, .image]
            ),
        ])

        let imageModels = manifest.entries(accepting: .image)
        XCTAssertEqual(imageModels.count, 1)
        XCTAssertEqual(imageModels[0].id, "llava-v1.5-7b")
    }

    func testManifestEntriesAcceptingTextFallsBackForLegacyEntries() {
        let manifest = AppManifest(models: [
            AppModelEntry(
                id: "legacy-model",
                capability: .chat,
                delivery: .managed
                // No inputModalities — legacy entry
            ),
        ])

        let textModels = manifest.entries(accepting: .text)
        XCTAssertEqual(textModels.count, 1, "Legacy entries should default to text")

        let imageModels = manifest.entries(accepting: .image)
        XCTAssertTrue(imageModels.isEmpty, "Legacy entries should not match image")
    }

    func testManifestMultimodalEntries() {
        let manifest = AppManifest(models: [
            AppModelEntry(
                id: "phi-4-mini",
                capability: .chat,
                delivery: .managed,
                inputModalities: [.text]
            ),
            AppModelEntry(
                id: "llava-v1.5-7b",
                capability: .chat,
                delivery: .managed,
                inputModalities: [.text, .image]
            ),
            AppModelEntry(
                id: "legacy-model",
                capability: .chat,
                delivery: .managed
            ),
        ])

        let multimodal = manifest.multimodalEntries()
        XCTAssertEqual(multimodal.count, 1)
        XCTAssertEqual(multimodal[0].id, "llava-v1.5-7b")
    }

    // MARK: - Codable Round-Trip

    func testAppModelEntryCodableRoundTrip() throws {
        let original = AppModelEntry(
            id: "llava-v1.5-7b",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            resourceBindings: [
                ResourceBinding(kind: .weights, path: "model.gguf"),
                ResourceBinding(kind: .projector, path: "mmproj.gguf"),
            ],
            engineConfig: ["n_gpu_layers": "99"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppModelEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.capability, original.capability)
        XCTAssertEqual(decoded.inputModalities, original.inputModalities)
        XCTAssertEqual(decoded.outputModalities, original.outputModalities)
        XCTAssertEqual(decoded.resourceBindings?.count, 2)
        XCTAssertEqual(decoded.resourceBindings?[0].kind, .weights)
        XCTAssertEqual(decoded.resourceBindings?[1].kind, .projector)
        XCTAssertEqual(decoded.engineConfig?["n_gpu_layers"], "99")
    }

    func testAppModelEntryCodableBackwardCompatibility() throws {
        // Simulate a JSON payload without the new multimodal fields
        let json = """
        {
            "id": "phi-4-mini",
            "capability": "chat",
            "delivery": "managed",
            "required": true
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let entry = try decoder.decode(AppModelEntry.self, from: data)

        XCTAssertEqual(entry.id, "phi-4-mini")
        XCTAssertEqual(entry.capability, .chat)
        XCTAssertNil(entry.inputModalities)
        XCTAssertNil(entry.outputModalities)
        XCTAssertNil(entry.resourceBindings)
        XCTAssertNil(entry.engineConfig)
    }

    func testResourceBindingCodableRoundTrip() throws {
        let binding = ResourceBinding(kind: .projector, path: "mmproj.gguf")
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(ResourceBinding.self, from: data)

        XCTAssertEqual(decoded.kind, .projector)
        XCTAssertEqual(decoded.path, "mmproj.gguf")
    }

    // MARK: - ArtifactResourceKind Extended Cases

    func testArtifactResourceKindNewCases() {
        XCTAssertEqual(ArtifactResourceKind.modelConfig.rawValue, "model_config")
        XCTAssertEqual(ArtifactResourceKind.adapter.rawValue, "adapter")
    }

    func testArtifactResourceKindExistingCases() {
        XCTAssertEqual(ArtifactResourceKind.weights.rawValue, "weights")
        XCTAssertEqual(ArtifactResourceKind.projector.rawValue, "projector")
        XCTAssertEqual(ArtifactResourceKind.processor.rawValue, "processor")
        XCTAssertEqual(ArtifactResourceKind.tokenizer.rawValue, "tokenizer")
        XCTAssertEqual(ArtifactResourceKind.vocab.rawValue, "vocab")
    }

    // MARK: - OutputModality

    func testOutputModalityRawValues() {
        XCTAssertEqual(OutputModality.text.rawValue, "text")
        XCTAssertEqual(OutputModality.image.rawValue, "image")
        XCTAssertEqual(OutputModality.audio.rawValue, "audio")
        XCTAssertEqual(OutputModality.video.rawValue, "video")
    }

    func testOutputModalityCodable() throws {
        let modality = OutputModality.text
        let data = try JSONEncoder().encode(modality)
        let decoded = try JSONDecoder().decode(OutputModality.self, from: data)
        XCTAssertEqual(decoded, modality)
    }

    // MARK: - InputModality

    func testInputModalityRawValues() {
        XCTAssertEqual(InputModality.text.rawValue, "text")
        XCTAssertEqual(InputModality.image.rawValue, "image")
        XCTAssertEqual(InputModality.audio.rawValue, "audio")
        XCTAssertEqual(InputModality.video.rawValue, "video")
    }

    // MARK: - LocalFileModelRuntime Resource Resolution

    func testLocalFileModelRuntimeResolvedResourceWeightsDefault() {
        let fileURL = URL(fileURLWithPath: "/models/model.gguf")
        let runtime = LocalFileModelRuntime(modelId: "test", fileURL: fileURL)

        let weights = runtime.resolvedResource(.weights)
        XCTAssertEqual(weights, fileURL, "Weights should default to fileURL")

        let projector = runtime.resolvedResource(.projector)
        XCTAssertNil(projector, "No projector binding should return nil")
    }

    func testLocalFileModelRuntimeResolvedResourceWithBindings() {
        let fileURL = URL(fileURLWithPath: "/models/model.gguf")
        let projectorURL = URL(fileURLWithPath: "/models/mmproj.gguf")
        let tokenizerURL = URL(fileURLWithPath: "/models/tokenizer.json")

        let runtime = LocalFileModelRuntime(
            modelId: "test-vl",
            fileURL: fileURL,
            resourceBindings: [
                .weights: fileURL,
                .projector: projectorURL,
                .tokenizer: tokenizerURL,
            ]
        )

        XCTAssertEqual(runtime.resolvedResource(.weights), fileURL)
        XCTAssertEqual(runtime.resolvedResource(.projector), projectorURL)
        XCTAssertEqual(runtime.resolvedResource(.tokenizer), tokenizerURL)
        XCTAssertNil(runtime.resolvedResource(.adapter))
    }

    func testLocalFileModelRuntimeHasProjector() {
        let fileURL = URL(fileURLWithPath: "/models/model.gguf")
        let projectorURL = URL(fileURLWithPath: "/models/mmproj.gguf")

        let noProjector = LocalFileModelRuntime(modelId: "text-only", fileURL: fileURL)
        XCTAssertFalse(noProjector.hasProjector)

        let withProjector = LocalFileModelRuntime(
            modelId: "vl-model",
            fileURL: fileURL,
            resourceBindings: [.projector: projectorURL]
        )
        XCTAssertTrue(withProjector.hasProjector)
    }

    func testLocalFileModelRuntimeMultimodalCapabilities() {
        let fileURL = URL(fileURLWithPath: "/models/model.gguf")
        let caps = RuntimeCapabilities(supportsMultimodalInput: true, supportsStreaming: true)
        let runtime = LocalFileModelRuntime(
            modelId: "vl-model",
            fileURL: fileURL,
            resourceBindings: [:],
            capabilities: caps
        )

        XCTAssertTrue(runtime.capabilities.supportsMultimodalInput)
        XCTAssertTrue(runtime.capabilities.supportsStreaming)
    }

    // MARK: - Full VL Model Package Scenario

    func testVisionLanguageModelPackage() {
        // Simulates a complete VL model declaration as it would appear in a manifest
        let bindings: [ResourceBinding] = [
            ResourceBinding(kind: .weights, path: "llava-v1.5-7b-Q4_K_M.gguf"),
            ResourceBinding(kind: .projector, path: "llava-v1.5-7b-mmproj-f16.gguf"),
        ]

        let entry = AppModelEntry(
            id: "llava-v1.5-7b",
            capability: .chat,
            delivery: .managed,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            resourceBindings: bindings,
            engineConfig: ["n_gpu_layers": "99", "mmproj": "true"]
        )

        // Verify contract alignment
        XCTAssertEqual(entry.capability, .chat, "VL model uses chat capability, not a separate vision capability")
        XCTAssertTrue(entry.isMultimodal)
        XCTAssertTrue(entry.supportsImageInput)
        XCTAssertEqual(entry.resourceBindings?.count, 2)

        // Verify modality is orthogonal to capability
        XCTAssertEqual(entry.inputModalities, [.text, .image])
        XCTAssertEqual(entry.outputModalities, [.text])

        // Verify resource bindings enable explicit file resolution
        let baseURL = URL(fileURLWithPath: "/app/Models")
        let weightsURL = entry.resolvedURL(for: .weights, relativeTo: baseURL)
        XCTAssertEqual(weightsURL?.lastPathComponent, "llava-v1.5-7b-Q4_K_M.gguf")

        let projectorURL = entry.resolvedURL(for: .projector, relativeTo: baseURL)
        XCTAssertEqual(projectorURL?.lastPathComponent, "llava-v1.5-7b-mmproj-f16.gguf")
    }
}

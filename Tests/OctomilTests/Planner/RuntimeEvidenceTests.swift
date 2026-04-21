import Foundation
import XCTest
@testable import Octomil

final class RuntimeEvidenceTests: XCTestCase {

    // MARK: - Metadata Key Constants

    func testMetadataKeyConstants() {
        XCTAssertEqual(RuntimeEvidenceMetadataKey.models, "models")
        XCTAssertEqual(RuntimeEvidenceMetadataKey.capabilities, "capabilities")
        XCTAssertEqual(RuntimeEvidenceMetadataKey.artifactDigest, "artifact_digest")
        XCTAssertEqual(RuntimeEvidenceMetadataKey.artifactFormat, "artifact_format")
    }

    // MARK: - modelCapable Factory

    func testModelCapableProducesValidRuntime() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "mlx",
            model: "llama-8b",
            capabilities: ["text"],
            version: "0.30.0",
            accelerator: "metal"
        )

        XCTAssertEqual(runtime.engine, "mlx-lm", "Engine should be canonicalized")
        XCTAssertEqual(runtime.version, "0.30.0")
        XCTAssertTrue(runtime.available)
        XCTAssertEqual(runtime.accelerator, "metal")
        XCTAssertEqual(runtime.metadata["models"], "llama-8b")
        XCTAssertEqual(runtime.metadata["capabilities"], "text")
    }

    func testModelCapableCanonicalizesMlxAlias() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "mlx_lm",
            model: "gemma-2b",
            capabilities: ["text"]
        )
        XCTAssertEqual(runtime.engine, "mlx-lm")
    }

    func testModelCapableCanonicalizesLlamaAlias() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "llamacpp",
            model: "phi-3",
            capabilities: ["text"]
        )
        XCTAssertEqual(runtime.engine, "llama.cpp")
    }

    func testModelCapableCanonicalizesWhisperAlias() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "whisper",
            model: "whisper-base",
            capabilities: ["audio_transcription"]
        )
        XCTAssertEqual(runtime.engine, "whisper.cpp")
    }

    func testModelCapableCanonicalizesWhisperCppAlias() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "whisper_cpp",
            model: "whisper-large-v3",
            capabilities: ["audio_transcription"]
        )
        XCTAssertEqual(runtime.engine, "whisper.cpp")
    }

    func testModelCapableCanonicalizesLlamaHyphenAlias() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "llama-cpp",
            model: "mistral-7b",
            capabilities: ["text"]
        )
        XCTAssertEqual(runtime.engine, "llama.cpp")
    }

    func testModelCapableLowercasesModelAndCapabilities() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "Llama-8B",
            capabilities: ["Text", "EMBEDDINGS"]
        )

        XCTAssertEqual(runtime.metadata["models"], "llama-8b")
        XCTAssertEqual(runtime.metadata["capabilities"], "text,embeddings")
    }

    func testModelCapableMultipleCapabilities() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "coreml",
            model: "whisper-tiny",
            capabilities: ["audio_transcription", "audio"]
        )

        XCTAssertEqual(runtime.metadata["capabilities"], "audio_transcription,audio")
    }

    func testModelCapableWithArtifactDigestAndFormat() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "phi-3",
            capabilities: ["text"],
            artifactDigest: "abc123def456",
            artifactFormat: "GGUF"
        )

        XCTAssertEqual(runtime.metadata["artifact_digest"], "abc123def456")
        XCTAssertEqual(runtime.metadata["artifact_format"], "gguf")
    }

    func testModelCapableWithoutOptionalFields() {
        let runtime = InstalledRuntime.modelCapable(
            engine: "mlx-lm",
            model: "tiny-model",
            capabilities: ["text"]
        )

        XCTAssertNil(runtime.version)
        XCTAssertNil(runtime.accelerator)
        XCTAssertNil(runtime.metadata["artifact_digest"])
        XCTAssertNil(runtime.metadata["artifact_format"])
    }

    // MARK: - Planner Integration

    func testPlannerMatchesModelCapableRuntime() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-evidence-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RuntimePlannerStore(cacheDirectory: tempDir)
        let planner = RuntimePlanner(store: store, client: nil)

        let evidence = InstalledRuntime.modelCapable(
            engine: "mlx",
            model: "gemma-2b",
            capabilities: ["text"],
            version: "0.30.0",
            accelerator: "metal"
        )

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.engine, "mlx-lm")
        XCTAssertEqual(selection.source, "local_default")
    }

    func testPlannerDoesNotMatchWrongModel() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-evidence-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RuntimePlannerStore(cacheDirectory: tempDir)
        let planner = RuntimePlanner(store: store, client: nil)

        let evidence = InstalledRuntime.modelCapable(
            engine: "mlx",
            model: "gemma-2b",
            capabilities: ["text"]
        )

        // Request a different model
        let selection = await planner.resolve(
            model: "llama-70b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        // Should NOT match the gemma-2b evidence
        XCTAssertEqual(selection.locality, .cloud)
        XCTAssertEqual(selection.source, "fallback")
    }

    func testPlannerDoesNotMatchWrongCapability() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-evidence-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RuntimePlannerStore(cacheDirectory: tempDir)
        let planner = RuntimePlanner(store: store, client: nil)

        let evidence = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "llama-8b",
            capabilities: ["text"]
        )

        // Request audio capability with a text-only runtime
        let selection = await planner.resolve(
            model: "llama-8b",
            capability: "audio_transcription",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .cloud)
        XCTAssertEqual(selection.source, "fallback")
    }

    func testFrameworkOnlyRuntimeDoesNotMatchWithoutEvidence() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-evidence-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RuntimePlannerStore(cacheDirectory: tempDir)
        let planner = RuntimePlanner(store: store, client: nil)

        // Register a runtime that is available but has no model/capability evidence
        let bareRuntime = InstalledRuntime(
            engine: "mlx",
            available: true
        )

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            allowNetwork: false,
            additionalRuntimes: [bareRuntime]
        )

        // Should fall back to cloud because bare runtime has no model evidence
        XCTAssertEqual(selection.locality, .cloud)
        XCTAssertEqual(selection.source, "fallback")
    }
}

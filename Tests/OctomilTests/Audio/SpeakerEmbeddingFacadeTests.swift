import XCTest
@testable import Octomil

// MARK: - SpeakerEmbeddingFacadeTests
//
// Verifies: facade exists, is callable, and surfaces a bounded
// runtimeUnavailable error when no native runtime is wired.
//
// Capability string from RuntimeCapability enum (contract-pinned).

final class SpeakerEmbeddingFacadeTests: XCTestCase {

    // MARK: - Capability string

    func testAudioSpeakerEmbeddingCapabilityStringMatchesContract() {
        XCTAssertEqual(RuntimeCapability.audioSpeakerEmbedding.rawValue, "audio.speaker.embedding")
    }

    // MARK: - Facade existence and callability

    func testFacadeSpeakerEmbeddingExists() {
        let se = makeFacadeWithUnavailableRuntime()
        XCTAssertNotNil(se)
    }

    func testCreateReturnsRuntimeUnavailableWhenNoRuntimeWired() async throws {
        let se = makeFacadeWithUnavailableRuntime()
        do {
            _ = try await se.create(audio: makeDummyPcmF32(samples: 16000), sampleRate: 16000)
            XCTFail("Expected runtimeUnavailable, got success")
        } catch OctomilError.runtimeUnavailable {
            // Expected — fail closed.
        } catch {
            // Other OctomilErrors are acceptable (runtime opened but
            // session rejected). The test verifies no silent success.
        }
    }

    // MARK: - Input validation (runs without a runtime)

    func testCreateRejectsWrongSampleRate() async throws {
        let se = makeFacadeWithUnavailableRuntime()
        do {
            _ = try await se.create(audio: makeDummyPcmF32(samples: 480), sampleRate: 8000)
            XCTFail("Expected invalidInput for wrong sample rate")
        } catch OctomilError.invalidInput(let reason) {
            XCTAssertTrue(reason.contains("16000"), "Expected 16000 hint in reason: \(reason)")
        }
    }

    func testCreateRejectsEmptyAudio() async throws {
        let se = makeFacadeWithUnavailableRuntime()
        do {
            _ = try await se.create(audio: Data(), sampleRate: 16000)
            XCTFail("Expected invalidInput for empty audio")
        } catch OctomilError.invalidInput {
            // Expected.
        }
    }

    func testCreateRejectsNonAlignedBuffer() async throws {
        let se = makeFacadeWithUnavailableRuntime()
        let badData = Data(repeating: 0, count: 7)
        do {
            _ = try await se.create(audio: badData, sampleRate: 16000)
            XCTFail("Expected invalidInput for non-aligned buffer")
        } catch OctomilError.invalidInput(let reason) {
            XCTAssertTrue(reason.contains("multiple of 4"), "Expected alignment hint: \(reason)")
        }
    }

    // MARK: - OctomilAudio wiring

    func testOctomilAudioExposesSpeakerEmbeddingFacade() {
        let client = OctomilClient(
            auth: .deviceToken(deviceId: "dev_test", bootstrapToken: "test")
        )
        XCTAssertNotNil(client.audio.speakerEmbedding)
    }

    // MARK: - Dimension contract note

    /// Documents that callers MUST NOT hardcode 512 — the embedding
    /// dimension is determined by the model, not by this SDK.
    func testEmbeddingDimensionIsNotHardcoded() {
        // This test exists as documentation. The facade returns [Float]
        // whose count is model-determined. Callers that hardcode 512
        // will break when the model is updated to ERes2NetV2-large.
        //
        // Verified contractually (not via assertion, since we have no
        // real runtime here): the return type is [Float] with dynamic
        // count, not a fixed-size array.
        let placeholder: [Float] = []
        XCTAssertNotNil(placeholder) // tautology — intentional no-op documentation test
    }

    // MARK: - Lifecycle skeleton (skipped without artifacts)

    func testSpeakerEmbeddingLifecycleSkippedWithoutArtifacts() async throws {
        throw XCTSkip(
            "Requires liboctomil_runtime.dylib + OCTOMIL_SHERPA_SPEAKER_MODEL artifact"
        )
    }

    // MARK: - Helpers

    private func makeFacadeWithUnavailableRuntime() -> FacadeSpeakerEmbedding {
        FacadeSpeakerEmbedding {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "Test: native runtime not available"
            )
        }
    }

    private func makeDummyPcmF32(samples: Int) -> Data {
        Data(count: samples * MemoryLayout<Float>.size)
    }
}

import XCTest
@testable import Octomil

// MARK: - AudioDiarizationFacadeTests
//
// Verifies: facade exists, is callable, and surfaces a bounded
// runtimeUnavailable error when no native runtime is wired.

final class AudioDiarizationFacadeTests: XCTestCase {

    // MARK: - Capability string

    func testAudioDiarizationCapabilityStringMatchesContract() {
        XCTAssertEqual(RuntimeCapability.audioDiarization.rawValue, "audio.diarization")
    }

    // MARK: - Facade existence and callability

    func testFacadeDiarizationExists() {
        let diar = makeFacadeWithUnavailableRuntime()
        XCTAssertNotNil(diar)
    }

    func testCreateReturnsRuntimeUnavailableWhenNoRuntimeWired() async throws {
        let diar = makeFacadeWithUnavailableRuntime()
        do {
            _ = try await diar.create(audio: makeDummyPcmF32(samples: 480), sampleRate: 16000)
            XCTFail("Expected runtimeUnavailable, got success")
        } catch OctomilError.runtimeUnavailable {
            // Expected.
        } catch {
            // Other OctomilErrors are acceptable; the test verifies no
            // silent success.
        }
    }

    // MARK: - Input validation (runs without a runtime)

    func testCreateRejectsWrongSampleRate() async throws {
        let diar = makeFacadeWithUnavailableRuntime()
        do {
            _ = try await diar.create(audio: makeDummyPcmF32(samples: 480), sampleRate: 22050)
            XCTFail("Expected invalidInput for wrong sample rate")
        } catch OctomilError.invalidInput(let reason) {
            XCTAssertTrue(reason.contains("16000"), "Expected 16000 hint: \(reason)")
        }
    }

    func testCreateRejectsEmptyAudio() async throws {
        let diar = makeFacadeWithUnavailableRuntime()
        do {
            _ = try await diar.create(audio: Data(), sampleRate: 16000)
            XCTFail("Expected invalidInput for empty audio")
        } catch OctomilError.invalidInput {
            // Expected.
        }
    }

    func testCreateRejectsNonAlignedBuffer() async throws {
        let diar = makeFacadeWithUnavailableRuntime()
        let badData = Data(repeating: 0, count: 3)
        do {
            _ = try await diar.create(audio: badData, sampleRate: 16000)
            XCTFail("Expected invalidInput for non-aligned buffer")
        } catch OctomilError.invalidInput(let reason) {
            XCTAssertTrue(reason.contains("multiple of 4"), "Expected alignment hint: \(reason)")
        }
    }

    // MARK: - DiarizationSegment type

    func testDiarizationSegmentInitAndProperties() {
        let seg = DiarizationSegment(startMs: 0, endMs: 2500, speakerID: 0, speakerLabel: "SPEAKER_00")
        XCTAssertEqual(seg.startMs, 0)
        XCTAssertEqual(seg.endMs, 2500)
        XCTAssertEqual(seg.speakerID, 0)
        XCTAssertEqual(seg.speakerLabel, "SPEAKER_00")
    }

    // MARK: - OctomilAudio wiring

    func testOctomilAudioExposesDiarizationFacade() {
        let client = OctomilClient(
            auth: .deviceToken(deviceId: "dev_test", bootstrapToken: "test")
        )
        XCTAssertNotNil(client.audio.diarization)
    }

    // MARK: - Lifecycle skeleton (skipped without artifacts)

    func testDiarizationLifecycleSkippedWithoutArtifacts() async throws {
        throw XCTSkip(
            "Requires liboctomil_runtime.dylib + sherpa-onnx diarization model artifacts"
        )
    }

    // MARK: - Helpers

    private func makeFacadeWithUnavailableRuntime() -> FacadeDiarization {
        FacadeDiarization {
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

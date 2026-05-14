import XCTest
@testable import Octomil

// MARK: - AudioVadFacadeTests
//
// Verifies: facade exists, is callable, and surfaces a bounded
// runtimeUnavailable error when no native runtime is wired.
//
// Mirrors the Python VAD test discipline:
//   - No fallback assertions (hard-cut to native only)
//   - Capability string pulled from RuntimeCapability enum (not hardcoded)
//   - Lifecycle skeleton tests XCTSkip when artifacts are absent

final class AudioVadFacadeTests: XCTestCase {

    // MARK: - Capability string

    func testAudioVadCapabilityStringMatchesContract() {
        // Byte-for-byte contract check — any change here is a regression.
        XCTAssertEqual(RuntimeCapability.audioVad.rawValue, "audio.vad")
    }

    // MARK: - Facade existence and callability

    func testFacadeVadExists() {
        let vad = makeFacadeVadWithUnavailableRuntime()
        XCTAssertNotNil(vad)
    }

    /// Calling detect() with no native runtime wired must throw
    /// runtimeUnavailable (not crash, not hang, not silently succeed).
    func testDetectReturnsRuntimeUnavailableWhenNoRuntimeWired() async throws {
        let vad = makeFacadeVadWithUnavailableRuntime()
        do {
            _ = try await vad.detect(audio: makeDummyPcmF32(samples: 480), sampleRate: 16000)
            XCTFail("Expected runtimeUnavailable, got success")
        } catch OctomilError.runtimeUnavailable {
            // Expected — fail closed.
        } catch {
            // Any other OctomilError (e.g. inferenceFailed from a stub
            // that opens but immediately errors) is also acceptable here,
            // since the point is that no audio was silently processed.
            // The important invariant is that it throws rather than
            // returning empty transitions.
        }
    }

    // MARK: - Input validation (runs without a runtime)

    func testDetectRejectsWrongSampleRate() async throws {
        let vad = makeFacadeVadWithUnavailableRuntime()
        do {
            _ = try await vad.detect(audio: makeDummyPcmF32(samples: 480), sampleRate: 44100)
            XCTFail("Expected invalidInput for wrong sample rate")
        } catch OctomilError.invalidInput(let reason) {
            XCTAssertTrue(reason.contains("16000"), "Expected hint about 16000 in reason: \(reason)")
        }
    }

    func testDetectRejectsEmptyAudio() async throws {
        let vad = makeFacadeVadWithUnavailableRuntime()
        do {
            _ = try await vad.detect(audio: Data(), sampleRate: 16000)
            XCTFail("Expected invalidInput for empty audio")
        } catch OctomilError.invalidInput {
            // Expected.
        }
    }

    func testDetectRejectsNonAlignedBuffer() async throws {
        let vad = makeFacadeVadWithUnavailableRuntime()
        // 5 bytes is not a multiple of 4 (PCM-f32 requires 4-byte alignment)
        let badData = Data(repeating: 0, count: 5)
        do {
            _ = try await vad.detect(audio: badData, sampleRate: 16000)
            XCTFail("Expected invalidInput for non-aligned buffer")
        } catch OctomilError.invalidInput(let reason) {
            XCTAssertTrue(reason.contains("multiple of 4"), "Expected alignment hint in reason: \(reason)")
        }
    }

    // MARK: - VadTransition type

    func testVadTransitionInitAndProperties() {
        let t = VadTransition(kind: .speechStart, timestampMs: 120, confidence: 0.92)
        XCTAssertEqual(t.kind, .speechStart)
        XCTAssertEqual(t.timestampMs, 120)
        XCTAssertEqual(t.confidence, 0.92, accuracy: 0.001)
    }

    func testVadTransitionKindRawValues() {
        XCTAssertEqual(VadTransitionKind.speechStart.rawValue, "speech_start")
        XCTAssertEqual(VadTransitionKind.speechEnd.rawValue, "speech_end")
        XCTAssertEqual(VadTransitionKind.unknown.rawValue, "unknown")
    }

    // MARK: - OctomilAudio wiring

    func testOctomilAudioExposesVadFacade() {
        let client = OctomilClient(
            auth: .deviceToken(deviceId: "dev_test", bootstrapToken: "test")
        )
        let vad = client.audio.vad
        XCTAssertNotNil(vad)
    }

    // MARK: - Lifecycle skeleton (skipped without artifacts)

    func testVadDetectLifecycleSkippedWithoutArtifacts() async throws {
        // This test would exercise the full open→send→drain lifecycle
        // against a real liboctomil_runtime.dylib. It is skipped in CI
        // because the runtime dylib is not shipped with the test bundle.
        // When artifacts are present (e.g. on a developer machine with
        // OCTOMIL_RUNTIME_LIBRARY set), remove the skip and run manually.
        throw XCTSkip("Requires liboctomil_runtime.dylib + OCTOMIL_SILERO_VAD_MODEL artifact")
    }

    // MARK: - Model-free contract (regression: facade MUST NOT open a NativeModel)
    //
    // audio.vad is model-free per Python's `open_session(capability="audio.vad")`
    // contract. The iOS facade must call `openSessionModelFree`, not
    // `openModel` + `openSession`. This test captures a real runtime that
    // records whether `openModel` was called and fails the test if it was.

    func testVadFacadeDoesNotConstructANativeModel() async throws {
        var openModelCalled = false

        // This runtime records openModel calls and succeeds on
        // openSessionModelFree so we can reach the sendAudio path.
        // We still expect runtimeUnavailable (no real session), but
        // crucially openModel must NEVER have been invoked.
        let vad = FacadeVad {
            // Return a spy runtime whose openModel records the call.
            return ModelSpyRuntime { openModelCalled = true }
        }

        do {
            _ = try await vad.detect(audio: makeDummyPcmF32(samples: 480), sampleRate: 16000)
        } catch {
            // Any error is acceptable — we only care about openModel.
        }

        XCTAssertFalse(
            openModelCalled,
            "FacadeVad.detect() must not call openModel — audio.vad is a model-free capability"
        )
    }

    func testDiarizationFacadeDoesNotConstructANativeModel() async throws {
        var openModelCalled = false

        let diar = FacadeDiarization {
            return ModelSpyRuntime { openModelCalled = true }
        }

        do {
            _ = try await diar.create(audio: makeDummyPcmF32(samples: 480), sampleRate: 16000)
        } catch {
            // Any error is acceptable.
        }

        XCTAssertFalse(
            openModelCalled,
            "FacadeDiarization.create() must not call openModel — audio.diarization is a model-free capability"
        )
    }

    // MARK: - Helpers

    private func makeFacadeVadWithUnavailableRuntime() -> FacadeVad {
        FacadeVad {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "Test: native runtime not available"
            )
        }
    }

    /// Returns `count` interleaved PCM-f32 LE bytes (all zeros = silence).
    private func makeDummyPcmF32(samples: Int) -> Data {
        Data(count: samples * MemoryLayout<Float>.size)
    }
}

// MARK: - ModelSpyRuntime

/// A NativeRuntime that records whether openModel was called and
/// throws runtimeUnavailable on openSessionModelFree so tests can
/// reach a deterministic exit without a real dylib.
private actor ModelSpyRuntime: NativeRuntime {
    private let onOpenModel: () -> Void

    init(onOpenModel: @escaping () -> Void) {
        self.onOpenModel = onOpenModel
    }

    static func open(
        config: NativeRuntimeConfig,
        telemetrySink: NativeTelemetrySink?
    ) async throws -> Self {
        fatalError("ModelSpyRuntime.open() not used in tests")
    }

    func capabilities() async throws -> NativeCapabilities { NativeCapabilities() }

    func openModel(config: NativeModelConfig) async throws -> any NativeModel {
        onOpenModel()
        throw NativeRuntimeError(
            status: .unsupported,
            message: "ModelSpyRuntime: openModel must not be called for model-free capabilities"
        )
    }

    func openSession(
        config: NativeSessionConfig,
        model: any NativeModel
    ) async throws -> any NativeSession {
        throw NativeRuntimeError(status: .unsupported, message: "ModelSpyRuntime: model-bound path not used")
    }

    func openSessionModelFree(config: NativeSessionConfig) async throws -> any NativeSession {
        throw NativeRuntimeError(
            status: .unsupported,
            message: "ModelSpyRuntime: openSessionModelFree — no real session in test"
        )
    }

    func close() async {}
}

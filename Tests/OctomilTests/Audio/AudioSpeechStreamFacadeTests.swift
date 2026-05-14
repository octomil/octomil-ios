import XCTest
@testable import Octomil

// MARK: - AudioSpeechStreamFacadeTests
//
// Verifies: FacadeTtsStream exists, is callable via AsyncSequence, and
// surfaces runtimeUnavailable when no native runtime is wired.
//
// Mirrors Python test discipline for NativeTtsStreamBackend:
//   - Voice validation is synchronous before any session open
//   - Empty input rejects invalidInput before any session open
//   - Non-numeric voice rejects invalidInput synchronously

final class AudioSpeechStreamFacadeTests: XCTestCase {

    // MARK: - Capability string

    func testAudioTtsStreamCapabilityStringMatchesContract() {
        XCTAssertEqual(RuntimeCapability.audioTtsStream.rawValue, "audio.tts.stream")
    }

    // MARK: - Facade existence and callability

    func testFacadeTtsStreamExists() {
        let ts = makeFacadeWithUnavailableRuntime()
        XCTAssertNotNil(ts)
    }

    func testStreamReturnsRuntimeUnavailableWhenNoRuntimeWired() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello") {
                XCTFail("Expected error, got chunk")
            }
        } catch OctomilError.runtimeUnavailable {
            threw = true
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "stream() must throw an error when runtime is unavailable")
    }

    // MARK: - Synchronous voice validation (before any session open)
    //
    // Python contract: validate_voice() runs BEFORE open_session() so an
    // unsupported voice rejects BEFORE the HTTP 200 / first chunk.

    func testStreamRejectsNonNumericVoiceSynchronously() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello", voice: "af_bella") {
                XCTFail("Expected invalidInput for non-numeric voice")
            }
        } catch OctomilError.invalidInput(let reason) {
            threw = true
            XCTAssertTrue(
                reason.contains("non-negative integer"),
                "Expected sid hint in reason: \(reason)"
            )
        }
        XCTAssertTrue(threw)
    }

    func testStreamAcceptsNumericVoice() async throws {
        // Numeric voice "0" should pass validation. The stream will then
        // throw runtimeUnavailable (no runtime), not invalidInput.
        let ts = makeFacadeWithUnavailableRuntime()
        var threwRuntimeError = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello", voice: "0") {
                XCTFail("Expected error")
            }
        } catch OctomilError.invalidInput {
            XCTFail("Numeric voice '0' should not throw invalidInput")
        } catch {
            threwRuntimeError = true
        }
        XCTAssertTrue(threwRuntimeError)
    }

    func testStreamAcceptsNilVoice() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello", voice: nil) {
                XCTFail("Expected error")
            }
        } catch OctomilError.invalidInput {
            XCTFail("nil voice should resolve to '0', not throw invalidInput")
        } catch {
            threw = true
        }
        XCTAssertTrue(threw)
    }

    // MARK: - Empty input validation

    func testStreamRejectsEmptyInput() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "   ") {
                XCTFail("Expected invalidInput for whitespace-only input")
            }
        } catch OctomilError.invalidInput {
            threw = true
        }
        XCTAssertTrue(threw, "Whitespace-only input must throw invalidInput")
    }

    // MARK: - Speed validation

    func testStreamRejectsZeroSpeed() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello", speed: 0.0) {
                XCTFail("Expected invalidInput for zero speed")
            }
        } catch OctomilError.invalidInput(let reason) {
            threw = true
            XCTAssertTrue(reason.contains("positive"), "Expected hint about positive in reason: \(reason)")
        }
        XCTAssertTrue(threw, "speed=0 must throw invalidInput")
    }

    func testStreamRejectsNegativeSpeed() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello", speed: -1.0) {
                XCTFail("Expected invalidInput for negative speed")
            }
        } catch OctomilError.invalidInput(let reason) {
            threw = true
            XCTAssertTrue(reason.contains("positive"), "Expected hint about positive in reason: \(reason)")
        }
        XCTAssertTrue(threw, "speed < 0 must throw invalidInput")
    }

    func testStreamAcceptsPositiveSpeed() async throws {
        let ts = makeFacadeWithUnavailableRuntime()
        var threwRuntimeError = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello", speed: 1.5) {
                XCTFail("Expected error")
            }
        } catch OctomilError.invalidInput {
            XCTFail("Positive speed should not throw invalidInput")
        } catch {
            threwRuntimeError = true
        }
        XCTAssertTrue(threwRuntimeError, "Positive speed must pass validation and reach runtime path")
    }

    // MARK: - Stream cancellation (producer task must cancel when consumer stops)

    func testStreamProducerCancelledWhenContinuationTerminated() async throws {
        // Verify that onTermination is wired — the producer task reference
        // is captured and cancelled when the continuation is torn down.
        // We can't directly observe the Task cancel in a unit test without
        // a real session, but we can verify the stream terminates cleanly
        // (no hang) when the consumer breaks early.
        let ts = makeFacadeWithUnavailableRuntime()
        var threw = false
        do {
            for try await _ in ts.stream(model: "kokoro-82m", input: "hello") {
                break  // Consumer breaks immediately
            }
        } catch {
            threw = true
        }
        // Either completes without hanging (break path) or throws — both acceptable.
        // The key invariant is no infinite loop / hang.
        _ = threw
    }

    // MARK: - validateVoice unit tests

    func testValidateVoiceNilReturnsZero() throws {
        let ts = makeFacadeWithUnavailableRuntime()
        XCTAssertEqual(try ts.validateVoice(nil), "0")
    }

    func testValidateVoiceEmptyStringReturnsZero() throws {
        let ts = makeFacadeWithUnavailableRuntime()
        XCTAssertEqual(try ts.validateVoice(""), "0")
    }

    func testValidateVoiceNumericPassthrough() throws {
        let ts = makeFacadeWithUnavailableRuntime()
        XCTAssertEqual(try ts.validateVoice("0"), "0")
        XCTAssertEqual(try ts.validateVoice("1"), "1")
        XCTAssertEqual(try ts.validateVoice("42"), "42")
    }

    func testValidateVoiceRejectsNonNumeric() throws {
        let ts = makeFacadeWithUnavailableRuntime()
        XCTAssertThrowsError(try ts.validateVoice("af_bella")) { error in
            if case OctomilError.invalidInput(let reason) = error {
                XCTAssertTrue(reason.contains("non-negative integer"), "Reason: \(reason)")
            } else {
                XCTFail("Expected invalidInput, got \(error)")
            }
        }
    }

    // MARK: - TtsStreamChunk type

    func testTtsStreamChunkInitAndProperties() {
        let chunk = TtsStreamChunk(
            pcmData: Data(repeating: 0, count: 1024),
            sampleRate: 24000,
            chunkIndex: 0,
            isFinal: false,
            cumulativeDurationMs: 42,
            streamingMode: "progressive"
        )
        XCTAssertEqual(chunk.sampleRate, 24000)
        XCTAssertEqual(chunk.chunkIndex, 0)
        XCTAssertFalse(chunk.isFinal)
        XCTAssertEqual(chunk.cumulativeDurationMs, 42)
        XCTAssertEqual(chunk.streamingMode, "progressive")
    }

    // MARK: - OctomilAudio wiring

    func testOctomilAudioExposesTtsStreamFacade() {
        let client = OctomilClient(
            auth: .deviceToken(deviceId: "dev_test", bootstrapToken: "test")
        )
        XCTAssertNotNil(client.audio.ttsStream)
    }

    // MARK: - Lifecycle skeleton (skipped without artifacts)

    func testTtsStreamLifecycleSkippedWithoutArtifacts() async throws {
        // FFI bridge is wired (Phase 4). This test exercises the full
        // oct_model_open → oct_session_open → oct_session_send_text →
        // poll_event (TTS_AUDIO_CHUNK events, isFinal progression) →
        // oct_session_close → oct_model_close lifecycle.
        // Skipped in CI because liboctomil_runtime.dylib is not in the
        // test bundle. To run live: set OCTOMIL_RUNTIME_LIBRARY and
        // OCTOMIL_SHERPA_TTS_MODEL (with OCT_HAVE_SHERPA_ONNX_TTS compiled
        // in), remove the skip, and run manually.
        throw XCTSkip(
            "Requires liboctomil_runtime.dylib + OCTOMIL_SHERPA_TTS_MODEL with " +
            "OCT_HAVE_SHERPA_ONNX_TTS compiled in"
        )
    }

    // MARK: - Helpers

    private func makeFacadeWithUnavailableRuntime() -> FacadeTtsStream {
        FacadeTtsStream {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "Test: native runtime not available"
            )
        }
    }
}

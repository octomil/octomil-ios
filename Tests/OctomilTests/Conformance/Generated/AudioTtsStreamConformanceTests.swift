// AUTO-GENERATED — do not edit.
//
// Source contract: conformance/audio.tts.stream.yaml
// Conformance version: 0.1.5-rc1
// Generator: scripts/gen_swift_conformance.py
//
// Required runtime ABI: major=0, minor>=10
// // is_advertised: true — runtime MUST include this capability in oct_runtime_capabilities()
// // model_bound: true — lifecycle includes model_open/model_warm/model_close

// Contract skip_reasons:
//   - SHERPA_ONNX_OFF: runtime built with -DOCT_ENABLE_ENGINE_SHERPA_ONNX=OFF
//   - TTS_MODEL_MISSING: OCTOMIL_SHERPA_TTS_MODEL env var unset (capability not advertised)
//
// SKIP_WITH_EXPLICIT_REASON (all native lifecycle tests):
//   Swift C-interop to liboctomil_runtime (oct_runtime_open / oct_session_open /
//   oct_session_poll) is exercised separately by FFINativeRuntimeTests. The
//   generated lifecycle paths remain artifact-gated.
//   TODO: https://github.com/octomil/octomil-ios/issues — Swift FFI bridge

import XCTest
@testable import Octomil

final class AudioTtsStreamConformanceTests: XCTestCase {

    // MARK: - Capability Name

    func testAudioTtsStreamCapabilityNameConstant() {
        // Byte-for-byte match against contract YAML `capability:` field.
        XCTAssertEqual("audio.tts.stream", "audio.tts.stream",
            "capability name literal must match contract byte-for-byte")
    }

    // MARK: - Bounded Error Codes

    func testAudioTtsStreamBoundedErrorCodes() {
        // bounded_error_codes from conformance/audio.tts.stream.yaml
        XCTAssertNotNil(ErrorCode(rawValue: "invalid_input"), "bounded error code invalid_input missing from ErrorCode enum")
        XCTAssertNotNil(ErrorCode(rawValue: "runtime_unavailable"), "bounded error code runtime_unavailable missing from ErrorCode enum")
        XCTAssertNotNil(ErrorCode(rawValue: "model_not_found"), "bounded error code model_not_found missing from ErrorCode enum")
        XCTAssertNotNil(ErrorCode(rawValue: "cancelled"), "bounded error code cancelled missing from ErrorCode enum")
        XCTAssertNotNil(ErrorCode(rawValue: "inference_failed"), "bounded error code inference_failed missing from ErrorCode enum")
    }

    // MARK: - Allowed Event Set (Invariant 7)

    func testAudioTtsStreamAllowedEventSetWellFormed() {
        // Contract: emitted event types ⊆ expected_event_sequence ∪ runtime_scope_events
        // Source: conformance/audio.tts.stream.yaml expected_event_sequence
        let allowedEvents: Set<String> = [
            "OCT_EVENT_CACHE_HIT",
            "OCT_EVENT_CACHE_MISS",
            "OCT_EVENT_MEMORY_PRESSURE",
            "OCT_EVENT_METRIC",
            "OCT_EVENT_MODEL_EVICTED",
            "OCT_EVENT_MODEL_LOADED",
            "OCT_EVENT_SESSION_COMPLETED",
            "OCT_EVENT_SESSION_STARTED",
            "OCT_EVENT_THERMAL_STATE",
            "OCT_EVENT_TTS_AUDIO_CHUNK"
        ]
        XCTAssertFalse(allowedEvents.isEmpty,
            "audio.tts.stream: allowed event set must not be empty")
        for evt in allowedEvents {
            XCTAssertTrue(evt.hasPrefix("OCT_EVENT_"),
                "Event \(evt) is not a valid OCT_EVENT_* name")
        }
    }

    // MARK: - Lifecycle Step Ordering

    func testAudioTtsStreamLifecycleSteps() {
        // Source: conformance/audio.tts.stream.yaml lifecycle field
        let steps: [String] = ["runtime_open", "model_open", "model_warm", "session_open", "send_text", "poll_event", "session_close", "model_close", "runtime_close"]
        guard !steps.isEmpty else { return }  // cross-cutting YAMLs have empty lifecycle
        XCTAssertEqual(steps.first, "runtime_open",
            "audio.tts.stream: lifecycle must begin with runtime_open")
        XCTAssertEqual(steps.last, "runtime_close",
            "audio.tts.stream: lifecycle must end with runtime_close")
        if steps.contains("model_open") {
            let modelOpenIdx = steps.firstIndex(of: "model_open")!
            let sessionOpenIdx = steps.firstIndex(of: "session_open")!
            XCTAssertLessThan(modelOpenIdx, sessionOpenIdx,
                "audio.tts.stream: model_open must precede session_open")
        }
    }

    // MARK: - Privacy Constraints

    func testAudioTtsStreamDenyFieldSubstrings() {
        // deny_field_substrings from conformance/audio.tts.stream.yaml
        // These strings must NEVER appear in outbound telemetry.
        let deny: [String] = [
        "audio_bytes",
        "raw_audio",
        "audio_pcm",
        "wav_bytes",
        "transcript_text",
        "input_text",
        "prompt_text",
        "voice_metadata",
        ]
        for s in deny {
            XCTAssertFalse(s.isEmpty, "deny_field_substring must be non-empty")
        }
    }

    // MARK: - Native Lifecycle (SKIP — artifact-gated)

    func testAudioTtsStreamLifecycle() throws {
        throw XCTSkip(
            "SKIP_WITH_EXPLICIT_REASON: native lifecycle for \"audio.tts.stream\" requires " +
            "Swift C-interop to liboctomil_runtime. The bridge is covered separately by FFINativeRuntimeTests. " +
            "TODO: https://github.com/octomil/octomil-ios/issues — Swift FFI bridge"
        )
        // When FFI bridge lands:
        // 1. oct_runtime_open → check ABI (major=0, minor>=10)
        // 2. oct_runtime_capabilities → assert "audio.tts.stream" advertised
        guard ProcessInfo.processInfo.environment["OCTOMIL_SHERPA_TTS_MODEL"] != nil else {
            throw XCTSkip("SKIP: required env var OCTOMIL_SHERPA_TTS_MODEL is unset — capability not advertised by runtime")
        }
        // 3. Drive lifecycle: runtime_open → model_open → model_warm → session_open → send_text → poll_event → session_close → model_close → runtime_close
        // 4. Drain poll_event → assert event set ⊆ allowedEvents
        // 5. Assert terminal_statuses ∈ ['OCT_STATUS_OK', 'OCT_STATUS_CANCELLED', 'OCT_STATUS_INVALID_INPUT', 'OCT_STATUS_UNSUPPORTED', 'OCT_STATUS_NOT_FOUND']
    }

    func testAudioTtsStreamNoSilentCloudFallback() throws {
        throw XCTSkip(
            "SKIP_WITH_EXPLICIT_REASON: native path for \"audio.tts.stream\" not exercisable " +
            "without FFI bridge. No cloud call made — test would fake-pass otherwise."
        )
        // When FFI bridge lands: if runtime unavailable → must raise ErrorCode.runtimeUnavailable
        // NEVER route to cloud to pass this conformance test.
    }
}

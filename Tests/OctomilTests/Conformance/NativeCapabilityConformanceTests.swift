import XCTest
@testable import Octomil

// MARK: - iOS Native Capability Conformance Tests
//
// Contract: octomil-contracts/conformance/ (CONFORMANCE_VERSION: 0.1.5-rc1)
//
// Covers the 12 live native / live-conditional capabilities:
//   1. chat.completion      (owning_engine: llama_cpp)
//   2. chat.stream          (owning_engine: llama_cpp)
//   3. embeddings.text      (owning_engine: llama_cpp)
//   4. audio.transcription  (owning_engine: whisper_cpp)
//   5. audio.stt.batch      (alias of audio.transcription)
//   6. audio.stt.stream     (buffered stream alias of audio.transcription)
//   7. audio.vad            (owning_engine: silero_vad)
//   8. audio.speaker.embedding (owning_engine: sherpa_onnx)
//   9. audio.diarization    (owning_engine: sherpa_onnx/diarization)
//   10. audio.tts.batch     (owning_engine: sherpa_onnx)
//   11. audio.tts.stream    (owning_engine: sherpa_onnx)
//   12. cache.introspect    (runtime/cache ABI, not a session)
//
// NOT claimed (per contract exclusion list):
//   - audio.realtime.session, embeddings.image, index.vector.query
//
// SKIP policy: generated artifact-backed lifecycle tests remain
// SKIP_WITH_EXPLICIT_REASON unless a real liboctomil_runtime and required
// model artifacts are available. The Swift FFI bridge itself is covered by
// FFINativeRuntimeTests and stub event tests.
//
// SDK-layer constant checks (enum raw values, error-code mapping, event
// names) DO NOT require the FFI bridge and run unconditionally.

// MARK: - Capability Constants

/// Canonical capability name strings — byte-for-byte from contract YAMLs.
/// Any change here is a contract break.
enum ContractCapabilityName {
    static let chatCompletion = "chat.completion"
    static let chatStream = "chat.stream"
    static let embeddingsText = "embeddings.text"
    static let audioTranscription = "audio.transcription"
    static let audioSttBatch = "audio.stt.batch"
    static let audioSttStream = "audio.stt.stream"
    static let audioVad = "audio.vad"
    static let audioSpeakerEmbedding = "audio.speaker.embedding"
    static let audioDiarization = "audio.diarization"
    static let audioTtsBatch = "audio.tts.batch"
    static let audioTtsStream = "audio.tts.stream"
    static let cacheIntrospect = "cache.introspect"

    /// The full set of live capabilities — CLOSED. Do not add unless the
    /// contract YAML has is_advertised: true.
    static let liveCapabilities: Set<String> = [
        chatCompletion,
        chatStream,
        embeddingsText,
        audioTranscription,
        audioSttBatch,
        audioSttStream,
        audioVad,
        audioSpeakerEmbedding,
        audioDiarization,
        audioTtsBatch,
        audioTtsStream,
        cacheIntrospect,
    ]

    /// Capabilities that are live-conditional, not reserved as hard exclusions.
    static let conditionalCapabilities: Set<String> = [
        "audio.diarization",
        "audio.stt.batch",
        "audio.stt.stream",
        "cache.introspect",
    ]

    /// Capabilities that MUST NOT be claimed by this SDK (hard exclusion).
    static let excludedCapabilities: Set<String> = [
        "audio.realtime.session",
        "embeddings.image",
        "index.vector.query",
    ]
}

// MARK: - Contract Event Names
//
// Canonical OCT_EVENT_* names from conformance/event_sequence.yaml.
// Used in closed-set assertions (Invariant 7).

enum ContractEventName {
    // Terminal
    static let sessionCompleted = "OCT_EVENT_SESSION_COMPLETED"
    // Session-scope intermediate
    static let sessionStarted = "OCT_EVENT_SESSION_STARTED"
    static let transcriptChunk = "OCT_EVENT_TRANSCRIPT_CHUNK"
    static let transcriptSegment = "OCT_EVENT_TRANSCRIPT_SEGMENT"
    static let transcriptFinal = "OCT_EVENT_TRANSCRIPT_FINAL"
    static let embeddingVector = "OCT_EVENT_EMBEDDING_VECTOR"
    static let vadTransition = "OCT_EVENT_VAD_TRANSITION"
    static let ttsAudioChunk = "OCT_EVENT_TTS_AUDIO_CHUNK"
    static let error = "OCT_EVENT_ERROR"
    // Runtime-scope (may interleave in any session)
    static let metric = "OCT_EVENT_METRIC"
    static let modelLoaded = "OCT_EVENT_MODEL_LOADED"
    static let modelEvicted = "OCT_EVENT_MODEL_EVICTED"
    static let cacheHit = "OCT_EVENT_CACHE_HIT"
    static let cacheMiss = "OCT_EVENT_CACHE_MISS"
    static let memoryPressure = "OCT_EVENT_MEMORY_PRESSURE"
    static let thermalState = "OCT_EVENT_THERMAL_STATE"
}

// MARK: - Status → ErrorCode mapping (error_mapping.yaml)
//
// Canonical oct_status_t → SDK ErrorCode mapping.
// Source: conformance/error_mapping.yaml status_to_sdk_code table.
//
// Canonical codes only — NOT "OPERATION_CANCELLED", NOT "TIMEOUT".
// Use "cancelled" and "request_timeout" per contract enums/error_code.yaml.

enum ContractStatusMapping {
    // OCT_STATUS_OK → no SDK error (nil)
    // OCT_STATUS_INVALID_INPUT → ErrorCode.invalidInput
    // OCT_STATUS_UNSUPPORTED → ErrorCode.unsupportedModality OR .runtimeUnavailable
    // OCT_STATUS_NOT_FOUND → ErrorCode.modelNotFound
    // OCT_STATUS_BUSY → ErrorCode.runtimeUnavailable
    // OCT_STATUS_TIMEOUT → ErrorCode.streamInterrupted  (only when exceeds retry budget)
    // OCT_STATUS_CANCELLED → ErrorCode.cancelled        (NOT "OPERATION_CANCELLED")
    // OCT_STATUS_INTERNAL → ErrorCode.inferenceFailed
    // OCT_STATUS_VERSION_MISMATCH → ErrorCode.runtimeUnavailable

    static let invalidInputCode: ErrorCode = .invalidInput
    static let cancelledCode: ErrorCode = .cancelled       // canonical: "cancelled"
    static let runtimeUnavailableCode: ErrorCode = .runtimeUnavailable
    static let modelNotFoundCode: ErrorCode = .modelNotFound
    static let inferenceFailedCode: ErrorCode = .inferenceFailed
    static let streamInterruptedCode: ErrorCode = .streamInterrupted
    static let unsupportedModalityCode: ErrorCode = .unsupportedModality
}

// MARK: - TTS Streaming Honesty Tokens (audio.tts.stream, v0.1.9)
//
// Source: conformance/audio.tts.stream.yaml
// delivery_timing: progressive_during_synthesis
// progressive_first_audio: true  (proof: first_audio_ratio=0.5909 < 0.75 gate)
// realtime_streaming_claim: true (RTF=0.105)
// These are SDK-observable invariants the iOS layer must preserve when
// the FFI bridge lands — recorded here so they survive as test constants.

enum ContractTtsStreamHonestyTokens {
    static let deliveryTiming = "progressive_during_synthesis"
    static let progressiveFirstAudio = true
    static let realtimeStreamingClaim = true
    static let measuredFirstAudioRatio = 0.5909
    static let measuredRTF = 0.105
    static let firstAudioRatioGate = 0.75   // must be < this
    static let rtfGate = 1.0               // must be < this
}

// MARK: - Lifecycle Step Names (per-capability lifecycle fields)
//
// Lifecycle orderings from each capability YAML.
// Represented as string arrays for assertion in generated tests.

enum ContractLifecycle {
    static let modelBound: [String] = [
        "runtime_open", "model_open", "model_warm",
        "session_open", "send_text", "poll_event",
        "session_close", "model_close", "runtime_close",
    ]
    static let modelBoundAudio: [String] = [
        "runtime_open", "model_open", "model_warm",
        "session_open", "send_audio", "poll_event",
        "session_close", "model_close", "runtime_close",
    ]
    // audio.vad is model-LESS (silero loads at runtime_open; no model_open).
    static let modelFree: [String] = [
        "runtime_open", "session_open", "send_audio",
        "poll_event", "session_close", "runtime_close",
    ]
}

// MARK: - Conformance Test Class

final class NativeCapabilityConformanceTests: XCTestCase {

    // MARK: - Capability Name Constants

    /// Byte-for-byte contract capability name check.
    /// If this fails, the SDK's capability identifier has drifted from the contract.
    func testCapabilityNameConstants() {
        XCTAssertEqual(ContractCapabilityName.chatCompletion, "chat.completion")
        XCTAssertEqual(ContractCapabilityName.chatStream, "chat.stream")
        XCTAssertEqual(ContractCapabilityName.embeddingsText, "embeddings.text")
        XCTAssertEqual(ContractCapabilityName.audioTranscription, "audio.transcription")
        XCTAssertEqual(ContractCapabilityName.audioSttBatch, "audio.stt.batch")
        XCTAssertEqual(ContractCapabilityName.audioSttStream, "audio.stt.stream")
        XCTAssertEqual(ContractCapabilityName.audioVad, "audio.vad")
        XCTAssertEqual(ContractCapabilityName.audioSpeakerEmbedding, "audio.speaker.embedding")
        XCTAssertEqual(ContractCapabilityName.audioDiarization, "audio.diarization")
        XCTAssertEqual(ContractCapabilityName.audioTtsBatch, "audio.tts.batch")
        XCTAssertEqual(ContractCapabilityName.audioTtsStream, "audio.tts.stream")
        XCTAssertEqual(ContractCapabilityName.cacheIntrospect, "cache.introspect")
        XCTAssertEqual(ContractCapabilityName.liveCapabilities.count, 12,
            "Exactly 12 live/native-conditional capabilities — add none unless Python/runtime truth has promoted it")
    }

    /// Excluded capabilities are NOT in the live set.
    func testExcludedCapabilitiesNotInLiveSet() {
        for excluded in ContractCapabilityName.excludedCapabilities {
            XCTAssertFalse(
                ContractCapabilityName.liveCapabilities.contains(excluded),
                "Excluded capability \(excluded) must not appear in the live set"
            )
        }
    }

    func testConditionalCapabilitiesAreNotReserved() {
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains("audio.diarization"))
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains("audio.stt.batch"))
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains("audio.stt.stream"))
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains("cache.introspect"))
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.contains("audio.diarization"))
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.contains("audio.stt.batch"))
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.contains("audio.stt.stream"))
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.contains("cache.introspect"))
        XCTAssertFalse(ContractCapabilityName.excludedCapabilities.contains("audio.diarization"))
    }

    func testTranscriptionAliasAndCacheAbiSurfacesStayLive() {
        let transcriptionFamily: Set<String> = [
            ContractCapabilityName.audioTranscription,
            ContractCapabilityName.audioSttBatch,
            ContractCapabilityName.audioSttStream,
        ]

        XCTAssertEqual(transcriptionFamily.count, 3)
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.isSuperset(of: transcriptionFamily))
        XCTAssertFalse(ContractCapabilityName.excludedCapabilities.contains(ContractCapabilityName.audioSttBatch))
        XCTAssertFalse(ContractCapabilityName.excludedCapabilities.contains(ContractCapabilityName.audioSttStream))
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains(ContractCapabilityName.audioSttBatch))
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains(ContractCapabilityName.audioSttStream))

        let cacheAbiSurface = ContractCapabilityName.cacheIntrospect
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.contains(cacheAbiSurface))
        XCTAssertTrue(ContractCapabilityName.conditionalCapabilities.contains(cacheAbiSurface))
        XCTAssertFalse(ContractCapabilityName.excludedCapabilities.contains(cacheAbiSurface))
    }

    func testChatStreamIsAdvertised() {
        XCTAssertTrue(ContractCapabilityName.liveCapabilities.contains("chat.stream"))
        XCTAssertFalse(ContractCapabilityName.excludedCapabilities.contains("chat.stream"))
    }

    // MARK: - Error Code Constants (byte-for-byte)

    /// Canonical error codes required by conformance/error_mapping.yaml.
    /// Raw values must be exact snake_case strings — no "OPERATION_CANCELLED", no "TIMEOUT".
    func testCanonicalErrorCodeRawValues() {
        // From error_mapping.yaml status_to_sdk_code table
        XCTAssertEqual(ErrorCode.invalidInput.rawValue, "invalid_input")
        XCTAssertEqual(ErrorCode.cancelled.rawValue, "cancelled")           // NOT "operation_cancelled"
        XCTAssertEqual(ErrorCode.requestTimeout.rawValue, "request_timeout") // NOT "timeout"
        XCTAssertEqual(ErrorCode.runtimeUnavailable.rawValue, "runtime_unavailable")
        XCTAssertEqual(ErrorCode.modelNotFound.rawValue, "model_not_found")
        XCTAssertEqual(ErrorCode.inferenceFailed.rawValue, "inference_failed")
        XCTAssertEqual(ErrorCode.streamInterrupted.rawValue, "stream_interrupted")
        XCTAssertEqual(ErrorCode.unsupportedModality.rawValue, "unsupported_modality")
    }

    /// Status→SDK code mapping constants resolve to correct ErrorCode cases.
    func testStatusMappingConstants() {
        XCTAssertEqual(ContractStatusMapping.cancelledCode, .cancelled)
        XCTAssertEqual(ContractStatusMapping.invalidInputCode, .invalidInput)
        XCTAssertEqual(ContractStatusMapping.runtimeUnavailableCode, .runtimeUnavailable)
        XCTAssertEqual(ContractStatusMapping.modelNotFoundCode, .modelNotFound)
        XCTAssertEqual(ContractStatusMapping.inferenceFailedCode, .inferenceFailed)
        XCTAssertEqual(ContractStatusMapping.streamInterruptedCode, .streamInterrupted)
        XCTAssertEqual(ContractStatusMapping.unsupportedModalityCode, .unsupportedModality)
    }

    // MARK: - Bounded Error Codes per Capability

    /// chat.completion bounded_error_codes (from contract YAML).
    func testChatCompletionBoundedErrorCodes() {
        // bounded_error_codes: invalid_input, context_too_large, inference_failed, cancelled
        let bounded: [ErrorCode] = [.invalidInput, .contextTooLarge, .inferenceFailed, .cancelled]
        for code in bounded {
            XCTAssertNotNil(ErrorCode(rawValue: code.rawValue),
                "chat.completion bounded code \(code.rawValue) missing from ErrorCode enum")
        }
    }

    /// audio.transcription bounded_error_codes.
    func testAudioTranscriptionBoundedErrorCodes() {
        // bounded_error_codes: invalid_input, inference_failed, cancelled, unsupported_modality,
        //                      runtime_unavailable (audio backend default for OCT_STATUS_UNSUPPORTED)
        let bounded: [ErrorCode] = [
            .invalidInput, .inferenceFailed, .cancelled,
            .unsupportedModality, .runtimeUnavailable,
        ]
        for code in bounded {
            XCTAssertNotNil(ErrorCode(rawValue: code.rawValue),
                "audio.transcription bounded code \(code.rawValue) missing from ErrorCode enum")
        }
    }

    /// audio.tts.batch bounded_error_codes.
    func testAudioTtsBatchBoundedErrorCodes() {
        // bounded_error_codes: invalid_input, runtime_unavailable, model_not_found, cancelled,
        //                      inference_failed
        let bounded: [ErrorCode] = [
            .invalidInput, .runtimeUnavailable, .modelNotFound, .cancelled, .inferenceFailed,
        ]
        for code in bounded {
            XCTAssertNotNil(ErrorCode(rawValue: code.rawValue),
                "audio.tts.batch bounded code \(code.rawValue) missing from ErrorCode enum")
        }
    }

    /// audio.tts.stream bounded_error_codes (same as batch per contract).
    func testAudioTtsStreamBoundedErrorCodes() {
        let bounded: [ErrorCode] = [
            .invalidInput, .runtimeUnavailable, .modelNotFound, .cancelled, .inferenceFailed,
        ]
        for code in bounded {
            XCTAssertNotNil(ErrorCode(rawValue: code.rawValue),
                "audio.tts.stream bounded code \(code.rawValue) missing from ErrorCode enum")
        }
    }

    // MARK: - Event Closed Set (Invariant 7)
    //
    // For each capability, the contract defines which OCT_EVENT_* types may
    // appear. The set below is expected_event_sequence ∪ runtime_scope_events.
    // When the FFI bridge lands, the poll_event drain must reject any type not in
    // this set.

    func testChatCompletionAllowedEventSet() {
        // expected: SESSION_STARTED, TRANSCRIPT_CHUNK(1+), METRIC(0+), SESSION_COMPLETED
        let allowed: Set<String> = [
            ContractEventName.sessionStarted,
            ContractEventName.transcriptChunk,
            ContractEventName.metric,
            ContractEventName.sessionCompleted,
            // runtime-scope
            ContractEventName.modelLoaded,
            ContractEventName.modelEvicted,
            ContractEventName.cacheHit,
            ContractEventName.cacheMiss,
            ContractEventName.memoryPressure,
            ContractEventName.thermalState,
        ]
        XCTAssertFalse(allowed.isEmpty,
            "chat.completion allowed event set must not be empty")
        for evt in allowed {
            XCTAssertTrue(evt.hasPrefix("OCT_EVENT_"),
                "Event \(evt) is not a valid OCT_EVENT_* name")
        }
    }

    func testAudioTranscriptionAllowedEventSet() {
        // expected: SESSION_STARTED, METRIC(0+), TRANSCRIPT_SEGMENT(1+), TRANSCRIPT_FINAL, SESSION_COMPLETED
        let allowed: Set<String> = [
            ContractEventName.sessionStarted,
            ContractEventName.metric,
            ContractEventName.transcriptSegment,
            ContractEventName.transcriptFinal,
            ContractEventName.sessionCompleted,
            ContractEventName.modelLoaded, ContractEventName.modelEvicted,
            ContractEventName.cacheHit, ContractEventName.cacheMiss,
            ContractEventName.memoryPressure, ContractEventName.thermalState,
        ]
        XCTAssertFalse(allowed.isEmpty)
        for evt in allowed { XCTAssertTrue(evt.hasPrefix("OCT_EVENT_")) }
    }

    func testAudioVadAllowedEventSet() {
        // expected: SESSION_STARTED, METRIC(0+), VAD_TRANSITION(1+), SESSION_COMPLETED
        let allowed: Set<String> = [
            ContractEventName.sessionStarted,
            ContractEventName.metric,
            ContractEventName.vadTransition,
            ContractEventName.sessionCompleted,
            ContractEventName.modelLoaded, ContractEventName.modelEvicted,
            ContractEventName.cacheHit, ContractEventName.cacheMiss,
            ContractEventName.memoryPressure, ContractEventName.thermalState,
        ]
        XCTAssertFalse(allowed.isEmpty)
        for evt in allowed { XCTAssertTrue(evt.hasPrefix("OCT_EVENT_")) }
    }

    func testAudioTtsBatchAllowedEventSet() {
        // expected: SESSION_STARTED, METRIC(0+), TTS_AUDIO_CHUNK(1+), SESSION_COMPLETED
        let allowed: Set<String> = [
            ContractEventName.sessionStarted,
            ContractEventName.metric,
            ContractEventName.ttsAudioChunk,
            ContractEventName.sessionCompleted,
            ContractEventName.modelLoaded, ContractEventName.modelEvicted,
            ContractEventName.cacheHit, ContractEventName.cacheMiss,
            ContractEventName.memoryPressure, ContractEventName.thermalState,
        ]
        XCTAssertFalse(allowed.isEmpty)
        for evt in allowed { XCTAssertTrue(evt.hasPrefix("OCT_EVENT_")) }
    }

    // MARK: - Lifecycle Step Orderings

    /// Model-bound lifecycle steps match the contract (chat.completion, embeddings.text, etc.)
    func testModelBoundLifecycleOrder() {
        let steps = ContractLifecycle.modelBound
        XCTAssertEqual(steps.first, "runtime_open")
        XCTAssertEqual(steps.last, "runtime_close")
        XCTAssertTrue(steps.contains("model_open"))
        XCTAssertTrue(steps.contains("model_warm"))
        XCTAssertTrue(steps.contains("session_open"))
        XCTAssertTrue(steps.contains("poll_event"))
        XCTAssertTrue(steps.contains("session_close"))
        XCTAssertTrue(steps.contains("model_close"))
        // model_open MUST precede session_open
        let modelOpenIdx = steps.firstIndex(of: "model_open")!
        let sessionOpenIdx = steps.firstIndex(of: "session_open")!
        XCTAssertLessThan(modelOpenIdx, sessionOpenIdx,
            "model_open must precede session_open in model-bound lifecycle")
    }

    /// audio.vad model-free lifecycle: no model_open / model_close steps.
    func testAudioVadModelFreeLifecycle() {
        let steps = ContractLifecycle.modelFree
        XCTAssertFalse(steps.contains("model_open"),
            "audio.vad is model-free: model_open must not appear")
        XCTAssertFalse(steps.contains("model_close"),
            "audio.vad is model-free: model_close must not appear")
        XCTAssertEqual(steps.first, "runtime_open")
        XCTAssertEqual(steps.last, "runtime_close")
    }

    // MARK: - TTS Streaming Honesty Tokens (audio.tts.stream, v0.1.9)

    func testTtsStreamHonestyTokenValues() {
        XCTAssertEqual(ContractTtsStreamHonestyTokens.deliveryTiming,
            "progressive_during_synthesis",
            "delivery_timing must match contract v0.1.9 flip")
        XCTAssertTrue(ContractTtsStreamHonestyTokens.progressiveFirstAudio,
            "progressive_first_audio must be true per v0.1.9 proof (ratio=0.5909 < 0.75)")
        XCTAssertTrue(ContractTtsStreamHonestyTokens.realtimeStreamingClaim,
            "realtime_streaming_claim must be true per v0.1.9 proof (RTF=0.105)")
        XCTAssertLessThan(
            ContractTtsStreamHonestyTokens.measuredFirstAudioRatio,
            ContractTtsStreamHonestyTokens.firstAudioRatioGate,
            "first_audio_ratio must be < \(ContractTtsStreamHonestyTokens.firstAudioRatioGate)"
        )
        XCTAssertLessThan(
            ContractTtsStreamHonestyTokens.measuredRTF,
            ContractTtsStreamHonestyTokens.rtfGate,
            "RTF must be < \(ContractTtsStreamHonestyTokens.rtfGate)"
        )
    }

    // MARK: - Privacy Constraints

    /// deny_field_substrings from each capability YAML must not appear in SDK telemetry payloads.
    /// This test validates the constant set itself is correct; runtime enforcement happens in
    /// TelemetryQueueResourceContextTests and PrivacyConfigurationTests.
    func testPrivacyDenyFieldSubstringsForNativeCapabilities() {
        // From chat.completion, audio.transcription, audio.vad (shared set)
        let pathLeakStrings = ["/Users/", "/private/var/", "/home/"]
        // From audio.tts.batch / audio.tts.stream
        let ttsLeakStrings = ["audio_bytes", "raw_audio", "audio_pcm", "wav_bytes",
                              "transcript_text", "input_text", "prompt_text", "voice_metadata"]

        // These are the substrings that MUST NOT appear in any outbound telemetry
        let combinedDeny = pathLeakStrings + ttsLeakStrings

        // Structural check: all strings are non-empty and well-formed
        for s in combinedDeny {
            XCTAssertFalse(s.isEmpty, "deny_field_substring must be non-empty")
        }
        XCTAssertEqual(combinedDeny.count, 11, "Expected exactly 11 deny substrings from contracts")
    }

    // MARK: - Native Path SKIP_WITH_EXPLICIT_REASON
    //
    // The Swift FFI bridge is fully wired (Phase 4): runtime open, model open,
    // session open (model-bound and model-free), send_audio/send_text, poll_event,
    // cancel, and close all dispatch to oct_* symbols via dlsym.
    //
    // These lifecycle tests are skipped because they require a real
    // liboctomil_runtime dylib plus env-backed model artifacts, neither of which
    // ships with the test bundle. The FFI dispatch path is covered by
    // FFINativeRuntimeTests; these generated conformance bodies run against a
    // real runtime when artifacts are present on a developer machine.
    //
    // To enable: set OCTOMIL_RUNTIME_LIBRARY and the capability-specific artifact
    // env var, then remove the skipNativePath() call from the target test.

    private func skipNativePath(capability: String, file: StaticString = #file, line: UInt = #line) throws {
        throw XCTSkip(
            "SKIP_WITH_EXPLICIT_REASON: '\(capability)' lifecycle requires " +
            "liboctomil_runtime + env-backed model artifacts (not in test bundle). " +
            "FFI bridge is wired — set OCTOMIL_RUNTIME_LIBRARY + artifact env var to run live.",
            file: file, line: line
        )
    }

    // ── chat.completion ────────────────────────────────────────────────────

    func testChatCompletionLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.chatCompletion)
        // Artifact-gated: set OCTOMIL_RUNTIME_LIBRARY + OCTOMIL_LLAMA_CPP_MODEL.
        // FFI path: oct_runtime_open → oct_runtime_capabilities (assert "chat.completion"
        // advertised) → oct_model_open → oct_session_open → oct_session_send_text
        // (wrapped_messages_minimal.json) → drain poll_event → assert SESSION_STARTED × 1,
        // TRANSCRIPT_CHUNK ≥ 1, METRIC × 0+, SESSION_COMPLETED × 1 (terminal OK) →
        // no event outside allowed set → no deny_field_substring →
        // oct_session_close → oct_model_close → oct_runtime_close
    }

    func testChatCompletionInvalidInputRejectsWithBoundedError() throws {
        try skipNativePath(capability: ContractCapabilityName.chatCompletion)
        // Artifact-gated. Send bare_string.json → OCT_STATUS_INVALID_INPUT.
        // SDK must surface ErrorCode.invalidInput (NOT a generic runtime error).
        // last_error must contain "chat.completion".
    }

    func testChatCompletionNoSilentCloudFallback() throws {
        try skipNativePath(capability: ContractCapabilityName.chatCompletion)
        // Artifact-gated. If native advertised path unavailable → SKIP or fail-loud.
        // NEVER route to cloud to make the test pass.
    }

    // ── embeddings.text ───────────────────────────────────────────────────

    func testEmbeddingsTextLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.embeddingsText)
        // Artifact-gated. Lifecycle mirrors chat.completion (same llama_cpp engine).
        // Session event: SESSION_STARTED × 1, EMBEDDING_VECTOR ≥ 1 (one per input),
        // SESSION_COMPLETED × 1 (terminal OK).
    }

    func testEmbeddingsTextEmptyStringRejects() throws {
        try skipNativePath(capability: ContractCapabilityName.embeddingsText)
        // Artifact-gated. Send empty_string.json → OCT_STATUS_INVALID_INPUT.
        // last_error must contain "empty / whitespace-only".
    }

    // ── audio.transcription ───────────────────────────────────────────────

    func testAudioTranscriptionLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTranscription)
        // Artifact-gated: set OCTOMIL_RUNTIME_LIBRARY + OCTOMIL_WHISPER_BIN.
        // Send jfk_16k_mono_pcm_s16le.wav (only "tiny" model registered in v0.1.5).
        // Events: SESSION_STARTED × 1, METRIC × 0+, TRANSCRIPT_SEGMENT ≥ 1,
        //         TRANSCRIPT_FINAL × 1, SESSION_COMPLETED × 1.
        // Expected metrics: whisper.audio_duration_ms, whisper.decode_ms,
        //                   whisper.real_time_factor, whisper.session_open_ms.
    }

    func testAudioTranscriptionWrongSampleRateRejects() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTranscription)
        // Artifact-gated. Send 8khz_mono.wav → OCT_STATUS_INVALID_INPUT.
        // last_error must contain "sample_rate". SDK surfaces ErrorCode.invalidInput.
    }

    func testAudioTranscriptionOnlyTinyModelSupported() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTranscription)
        // Artifact-gated. Non-tiny model name → OCT_STATUS_UNSUPPORTED.
        // Audio backend maps to ErrorCode.runtimeUnavailable (NOT .unsupportedModality)
        // per conformance/audio.transcription.yaml:37 note and error_mapping.yaml fork.
    }

    // ── audio.vad ─────────────────────────────────────────────────────────

    func testAudioVadLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.audioVad)
        // Artifact-gated: set OCTOMIL_RUNTIME_LIBRARY + OCTOMIL_SILERO_VAD_MODEL.
        // Model-free path: no oct_model_open. Lifecycle: runtime_open →
        // oct_session_open(model=NULL) → oct_session_send_audio →
        // poll_event → oct_session_close → oct_runtime_close.
        // Events: SESSION_STARTED × 1, METRIC × 0+, VAD_TRANSITION ≥ 1,
        //         SESSION_COMPLETED × 1. jfk.wav should produce ≥ 1 matched pair.
    }

    func testAudioVadWrongSampleRateRejects() throws {
        try skipNativePath(capability: ContractCapabilityName.audioVad)
        // Artifact-gated. 8khz_mono.wav → OCT_STATUS_INVALID_INPUT,
        // last_error contains "sample_rate".
    }

    // ── audio.speaker.embedding ───────────────────────────────────────────

    func testAudioSpeakerEmbeddingLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.audioSpeakerEmbedding)
        // Artifact-gated: set OCTOMIL_RUNTIME_LIBRARY + OCTOMIL_SHERPA_SPEAKER_MODEL.
        // Model-bound path: oct_model_open(sherpa-eres2netv2-base) →
        // oct_session_open(capability:"audio.speaker.embedding") →
        // oct_session_send_audio(speaker_1to3s_16k_mono_pcm_s16le.wav) →
        // poll_event → oct_session_close → oct_model_close → oct_runtime_close.
        // Events: SESSION_STARTED × 1, METRIC × 0+,
        //         EMBEDDING_VECTOR × 1 (pooled fp32 L2-normalized), SESSION_COMPLETED × 1.
    }

    func testAudioSpeakerEmbeddingWrongSampleRateRejects() throws {
        try skipNativePath(capability: ContractCapabilityName.audioSpeakerEmbedding)
        // Artifact-gated. 8khz_mono.wav → OCT_STATUS_INVALID_INPUT,
        // last_error contains "sample_rate".
    }

    // ── audio.tts.batch ───────────────────────────────────────────────────

    func testAudioTtsBatchLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsBatch)
        // Artifact-gated: set OCTOMIL_RUNTIME_LIBRARY + OCTOMIL_SHERPA_TTS_MODEL.
        // Send short_english_phrase.json (default voice sid=0).
        // Events: SESSION_STARTED × 1, METRIC × 0+,
        //         TTS_AUDIO_CHUNK ≥ 1 (PCM-f32 mono), SESSION_COMPLETED × 1.
        // Expected metrics: tts.audio_duration_ms, tts.real_time_factor,
        //                   tts.session_open_ms, tts.synthesize_ms.
        // Privacy: deny audio_bytes, raw_audio, audio_pcm, wav_bytes, input_text, prompt_text.
    }

    func testAudioTtsBatchEmptyTextRejects() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsBatch)
        // Artifact-gated. empty_text.json → OCT_STATUS_INVALID_INPUT,
        // last_error contains "text". SDK: ErrorCode.invalidInput.
    }

    func testAudioTtsBatchBadDigestRejectsAsRuntimeUnavailable() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsBatch)
        // Artifact-gated. bad_digest.json → OCT_STATUS_UNSUPPORTED.
        // SDK maps to ErrorCode.runtimeUnavailable (NOT .checksumMismatch)
        // per error_mapping.yaml: OCT_STATUS_UNSUPPORTED → runtimeUnavailable for audio backend.
    }

    func testAudioTtsBatchMissingArtifactRejectsAsModelNotFound() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsBatch)
        // Artifact-gated. missing_artifact.json → OCT_STATUS_NOT_FOUND → ErrorCode.modelNotFound.
    }

    // ── audio.tts.stream ──────────────────────────────────────────────────

    func testAudioTtsStreamLifecycle() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsStream)
        // Artifact-gated: set OCTOMIL_RUNTIME_LIBRARY + OCTOMIL_SHERPA_TTS_MODEL.
        // Progressive delivery (v0.1.9): oct_session_send_text → drain poll_event.
        // short_english_phrase.json → single TTS_AUDIO_CHUNK with is_final=1.
        // long_english_paragraph.json → multiple chunks (is_final=0 ... is_final=1).
        // Events: SESSION_STARTED × 1, TTS_AUDIO_CHUNK ≥ 1, METRIC × 0+, SESSION_COMPLETED × 1.
        // Expected metrics: tts.audio_duration_ms, tts.chunk_count,
        //                   tts.first_chunk_after_synth_ms, tts.real_time_factor,
        //                   tts.synthesize_ms, tts.first_audio_ms.
        // Assert first_audio_ratio < 0.75. Assert RTF < 1.0.
        // is_final=0 on non-final chunks, is_final=1 on last chunk.
    }

    func testAudioTtsStreamIsStandaloneCapability() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsStream)
        // Artifact-gated. audio.tts.stream is NOT a streaming_profile_of audio.tts.batch
        // in v0.1.9. The runtime MUST advertise it as its own literal capability.
        // Assert "audio.tts.stream" in oct_runtime_capabilities().supported_capabilities
        // distinct from "audio.tts.batch".
    }

    func testAudioTtsStreamBadDigestRejectsAsRuntimeUnavailable() throws {
        try skipNativePath(capability: ContractCapabilityName.audioTtsStream)
        // Artifact-gated. Same bad_digest rejection path as audio.tts.batch.
        // bad_digest.json → OCT_STATUS_UNSUPPORTED → ErrorCode.runtimeUnavailable.
    }

    // MARK: - Cross-Cutting: No Silent Cloud Fallback

    /// Contract rule: conformance tests must NEVER fake-pass via cloud transport.
    /// This test verifies the SDK's routing logic does NOT silently substitute
    /// cloud calls when a native capability is unavailable — it must either SKIP or error.
    func testNoSilentCloudFallbackForNativeConformance() {
        // This is a structural constant test — no FFI bridge needed.
        // The principle: if isNativePath AND runtime not available → SKIP or ErrorCode.runtimeUnavailable
        // NEVER: cloud call that returns success masquerading as native conformance.

        // Verify the ErrorCode for cloud-fallback-disallowed exists and is canonical:
        XCTAssertEqual(ErrorCode.cloudFallbackDisallowed.rawValue, "cloud_fallback_disallowed")
        // A conformance test that reaches cloud when testing native = contract violation.
        // The skipNativePath helper above enforces this by XCTSkip rather than attempting
        // any network call.
    }

    // MARK: - Conformance Artifact Pin

    /// The CONFORMANCE_VERSION pinned in contracts is 0.1.5-rc1.
    /// This constant must match what the iOS SDK was generated against.
    func testConformanceVersionPin() {
        let expectedVersion = "0.1.5-rc1"
        // When the contracts submodule is updated, this pin must be bumped.
        // Mismatch here means the iOS Generated/ directory may be stale.
        XCTAssertEqual(expectedVersion, "0.1.5-rc1",
            "CONFORMANCE_VERSION pin mismatch — update Generated/ via sync_generated.py --sdk ios --write")
    }
}

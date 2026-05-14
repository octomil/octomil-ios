import Foundation

// MARK: - TtsStreamChunk

/// One sentence-bounded PCM chunk yielded by
/// ``FacadeTtsStream/stream(model:input:voice:speed:)``.
///
/// Mirrors Python ``TtsAudioChunk`` from
/// `octomil/runtime/native/tts_stream_backend.py`.
///
/// v0.1.9 delivery model: chunks are emitted progressively during
/// synthesis (``streamingMode == "progressive"``). The first chunk
/// arrives at ~59% of total synthesis wall-clock on the reference
/// runtime build; callers can begin playback on the first chunk
/// received rather than buffering everything.
///
/// - ``pcmData``: Raw PCM bytes. The runtime emits
///   ``OCT_SAMPLE_FORMAT_PCM_F32LE`` (32-bit float, mono).
/// - ``sampleRate``: Sample rate in Hz (e.g. 24 000).
/// - ``chunkIndex``: 0-based index of this chunk within the stream.
/// - ``isFinal``: True on the last chunk; the ``AsyncSequence``
///   terminates after yielding this element.
/// - ``cumulativeDurationMs``: Total audio duration accumulated
///   through this chunk, in milliseconds.
/// - ``streamingMode``: ``"progressive"`` for v0.1.9+ runtime;
///   ``"coalesced"`` for older builds.
public struct TtsStreamChunk: Sendable {
    public let pcmData: Data
    public let sampleRate: Int
    public let chunkIndex: Int
    public let isFinal: Bool
    public let cumulativeDurationMs: Int
    public let streamingMode: String

    public init(
        pcmData: Data,
        sampleRate: Int,
        chunkIndex: Int,
        isFinal: Bool,
        cumulativeDurationMs: Int,
        streamingMode: String = "progressive"
    ) {
        self.pcmData = pcmData
        self.sampleRate = sampleRate
        self.chunkIndex = chunkIndex
        self.isFinal = isFinal
        self.cumulativeDurationMs = cumulativeDurationMs
        self.streamingMode = streamingMode
    }
}

// MARK: - FacadeTtsStream

/// Streaming TTS facade: ``client.audio.speech.stream(...)``.
///
/// Mirrors Python's ``NativeTtsStreamBackend.synthesize_with_chunks()``
/// from `octomil/runtime/native/tts_stream_backend.py` and the
/// `/v1/audio/speech` SSE route that wraps it.
///
/// Returns an `AsyncThrowingStream<TtsStreamChunk, Error>` that yields
/// sentence-bounded PCM-f32 chunks as they arrive from the runtime.
///
/// ## Fail-closed contract
/// Hard-cut to native. No cloud fallback. The runtime must advertise
/// ``audio.tts.stream``; when it doesn't (missing model artifact,
/// engine not compiled in, or ABI mismatch), the stream throws
/// ``OctomilError/runtimeUnavailable(reason:)`` on the first next()
/// call.
///
/// ## Voice validation
/// Sherpa-onnx accepts numeric speaker-id strings only
/// (``"0"``, ``"1"``…). Passing a non-numeric voice throws
/// ``OctomilError/invalidInput(reason:)`` synchronously before any
/// session is opened — mirrors the Python ``validate_voice`` guard.
///
/// ## Usage
/// ```swift
/// for try await chunk in client.audio.speech.stream(
///     model: "kokoro-82m", input: "Hello world"
/// ) {
///     audioPlayer.append(chunk.pcmData)
///     if chunk.isFinal { audioPlayer.finish() }
/// }
/// ```
///
/// When ``liboctomil_runtime.dylib`` is loaded and the sherpa-onnx TTS
/// model is present, calls route through the FFI session lifecycle and
/// stream real PCM-f32 chunks. When the dylib is absent, the stream
/// throws ``OctomilError/runtimeUnavailable(reason:)`` on the first
/// ``next()`` call.
public final class FacadeTtsStream: @unchecked Sendable {

    // MARK: - Dependencies

    private let nativeRuntimeProvider: @Sendable () async throws -> any NativeRuntime

    // MARK: - Init

    /// Create with a native runtime provider closure.
    public init(
        nativeRuntimeProvider: @escaping @Sendable () async throws -> any NativeRuntime
    ) {
        self.nativeRuntimeProvider = nativeRuntimeProvider
    }

    // MARK: - stream

    /// Synthesize speech and stream PCM chunks as they arrive.
    ///
    /// Mirrors Python `NativeTtsStreamBackend.synthesize_with_chunks()`
    /// and the `/v1/audio/speech` SSE streaming route.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. ``"kokoro-82m"``).
    ///   - input: Non-empty text to synthesize.
    ///   - voice: Numeric speaker-id string (e.g. ``"0"``). ``nil`` →
    ///     model default (sid=0). Non-numeric strings throw
    ///     ``OctomilError/invalidInput(reason:)`` synchronously.
    ///   - speed: Speech rate multiplier (default 1.0).
    /// - Returns: `AsyncThrowingStream` yielding ``TtsStreamChunk``
    ///   elements progressively. The stream terminates after the
    ///   chunk with ``isFinal == true``.
    /// - Throws: ``OctomilError/runtimeUnavailable(reason:)`` when
    ///   ``liboctomil_runtime.dylib`` is unavailable or the sherpa-onnx
    ///   TTS model artifact is not present.
    public func stream(
        model: String,
        input: String,
        voice: String? = nil,
        speed: Float = 1.0
    ) -> AsyncThrowingStream<TtsStreamChunk, Error> {
        // Voice validation is synchronous (before any session open),
        // mirroring Python's validate_voice() contract: non-numeric
        // voice must reject BEFORE the HTTP 200 / first chunk.
        let resolvedVoice: String
        do {
            resolvedVoice = try validateVoice(voice)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        // Speed validation: positive non-zero value only. Zero and
        // negatives are a behavioral contract violation.
        // NOTE: speed is NOT forwarded to the native session config — the
        // runtime ABI has no speed field in oct_session_config_t. Speed
        // is reserved for the future iOS frontend-cache normalization
        // pipeline (mirrors Python's speed_x1000 cache-key encoding).
        // Callers passing speed != 1.0 get syntactically valid output at
        // the model's default rate until that pipeline lands.
        guard speed > 0 else {
            let error = OctomilError.invalidInput(
                reason: "audio.tts.stream: speed must be positive; got \(speed)"
            )
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let error = OctomilError.invalidInput(
                reason: "audio.tts.stream: `input` must be a non-empty string"
            )
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let runtimeProvider = nativeRuntimeProvider

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    let runtime: any NativeRuntime
                    do {
                        runtime = try await runtimeProvider()
                    } catch let nre as NativeRuntimeError {
                        throw OctomilError.runtimeUnavailable(
                            reason: "audio.tts.stream: native runtime unavailable — \(nre.message ?? "unknown")"
                        )
                    }

                    let modelConfig = NativeModelConfig(
                        modelURI: model,
                        artifactDigest: "",
                        engineHint: "sherpa_onnx"
                    )

                    let nativeModel: any NativeModel
                    do {
                        nativeModel = try await runtime.openModel(config: modelConfig)
                    } catch let nre as NativeRuntimeError {
                        throw nativeRuntimeErrorToOctomilError(
                            nre, capability: "audio.tts.stream", operation: "openModel"
                        )
                    }

                    let sessionConfig = NativeSessionConfig(
                        modelURI: model,
                        capability: RuntimeCapability.audioTtsStream.rawValue,
                        locality: "on-device",
                        policyPreset: "private",
                        speakerID: resolvedVoice,
                        sampleRateOut: 24000,
                        priority: .foreground
                    )

                    let session: any NativeSession
                    do {
                        session = try await runtime.openSession(
                            config: sessionConfig,
                            model: nativeModel
                        )
                    } catch let nre as NativeRuntimeError {
                        try? await nativeModel.close()
                        throw nativeRuntimeErrorToOctomilError(
                            nre, capability: "audio.tts.stream", operation: "openSession"
                        )
                    }

                    // send_text is synchronous before yielding first chunk —
                    // mirrors Python's "send_text MUST be synchronous BEFORE
                    // any StreamingResponse begins" contract.
                    do {
                        try await session.sendText(input)
                    } catch let nre as NativeRuntimeError {
                        await session.close()
                        try? await nativeModel.close()
                        throw nativeRuntimeErrorToOctomilError(
                            nre, capability: "audio.tts.stream", operation: "sendText"
                        )
                    }

                    // Drain and yield chunks
                    var chunkIndex = 0
                    var cumulativeSamples = 0
                    var cumulativeSampleRate = 0
                    let deadline = Date().addingTimeInterval(300)

                    defer {
                        Task { await session.close() }
                        Task { try? await nativeModel.close() }
                    }

                    while Date() < deadline {
                        // Check for cooperative cancellation: if the consumer
                        // stopped iterating and cancelled the parent task,
                        // stop polling to avoid keeping session resources alive.
                        try Task.checkCancellation()

                        let event: NativeEvent?
                        do {
                            event = try await session.pollEvent(timeout: 0.2)
                        } catch let nre as NativeRuntimeError {
                            throw nativeRuntimeErrorToOctomilError(
                                nre, capability: "audio.tts.stream", operation: "pollEvent"
                            )
                        }

                        guard let ev = event else { continue }

                        switch ev {
                        case .sessionStarted:
                            continue
                        case .ttsAudioChunk(let payload, _):
                            let sampleRate = Int(payload.sampleRate)
                            cumulativeSamples += payload.pcm.count / MemoryLayout<Float>.size
                            cumulativeSampleRate = sampleRate
                            let durMs = cumulativeSampleRate > 0
                                ? (cumulativeSamples * 1000) / cumulativeSampleRate
                                : 0
                            let chunk = TtsStreamChunk(
                                pcmData: payload.pcm,
                                sampleRate: sampleRate,
                                chunkIndex: chunkIndex,
                                isFinal: payload.isFinal,
                                cumulativeDurationMs: durMs,
                                streamingMode: "progressive"
                            )
                            continuation.yield(chunk)
                            chunkIndex += 1
                            if payload.isFinal {
                                continuation.finish()
                                return
                            }
                        case .error(let payload, _):
                            throw OctomilError.inferenceFailed(
                                reason: "audio.tts.stream: runtime error — \(payload.message) (code: \(payload.code))"
                            )
                        case .sessionCompleted(let payload, _):
                            if payload.terminalStatus != .ok {
                                throw OctomilError.inferenceFailed(
                                    reason: "audio.tts.stream: session terminated with status: \(payload.terminalStatus)"
                                )
                            }
                            // SESSION_COMPLETED(OK) without a prior isFinal=true chunk
                            // is an inference error.
                            throw OctomilError.inferenceFailed(
                                reason: "audio.tts.stream: SESSION_COMPLETED(OK) without a preceding isFinal chunk"
                            )
                        default:
                            continue
                        }
                    }

                    throw OctomilError.requestTimeout

                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Cancel the producer task when the consumer stops iterating
            // early (break / Task cancellation from the caller side).
            // Without this, the poll loop can keep running until timeout,
            // holding session + model resources after the consumer is gone.
            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }

    // MARK: - Voice validation

    /// Validate and resolve a voice to a numeric speaker-id string.
    ///
    /// Mirrors Python's ``NativeTtsStreamBackend.validate_voice()``
    /// logic: sherpa-onnx accepts non-negative integer sid strings.
    /// ``nil`` / ``""`` → ``"0"`` (model default). Non-numeric values
    /// throw ``OctomilError/invalidInput(reason:)``.
    func validateVoice(_ voice: String?) throws -> String {
        guard let voice = voice, !voice.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "0"
        }
        let v = voice.trimmingCharacters(in: .whitespaces)
        guard v.allSatisfy({ $0.isNumber }) else {
            throw OctomilError.invalidInput(
                reason: "audio.tts.stream: voice '\(voice)' is not a non-negative integer sid string. " +
                    "sherpa-onnx accepts numeric speaker ids only at the runtime ABI; " +
                    "pass voice=\"0\" for the model default."
            )
        }
        return v
    }
}

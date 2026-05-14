import Foundation

// MARK: - VadTransitionKind

/// Voice-activity transition kind. Mirrors `OCT_VAD_TRANSITION_*` constants
/// from the runtime ABI and `VadTransition.kind` in the Python SDK.
public enum VadTransitionKind: String, Sendable {
    case speechStart = "speech_start"
    case speechEnd = "speech_end"
    /// Forward-compat sentinel — never emitted by v0.1.5+, but a future
    /// runtime may. Callers MUST NOT crash on this value.
    case unknown = "unknown"
}

// MARK: - VadTransition

/// One voice-activity edge returned by ``FacadeVad/detect(audio:sampleRate:)``.
///
/// Mirrors Python ``VadTransition`` in
/// `octomil/runtime/native/vad_backend.py`.
///
/// - ``kind``: Whether speech started or ended.
/// - ``timestampMs``: Runtime-monotonic offset from the start of the
///   submitted audio clip, in milliseconds.
/// - ``confidence``: Silero per-window average speech probability across
///   the span, clamped to `[0, 1]` by the runtime.
public struct VadTransition: Sendable {
    public let kind: VadTransitionKind
    public let timestampMs: Int
    public let confidence: Float

    public init(kind: VadTransitionKind, timestampMs: Int, confidence: Float) {
        self.kind = kind
        self.timestampMs = timestampMs
        self.confidence = confidence
    }
}

// MARK: - FacadeVad

/// Public Swift facade for the ``audio.vad`` capability.
///
/// Mirrors Python's `octomil.audio.vad.open_vad_backend()` API.
///
/// ## Fail-closed contract
/// This facade routes exclusively through the native runtime. When the
/// runtime is unavailable (no `liboctomil_runtime.dylib`, missing
/// `OCTOMIL_SILERO_VAD_MODEL`, or ABI mismatch), every call throws
/// ``OctomilError/runtimeUnavailable(reason:)`` — there is no Python
/// fallback and there is no cloud path. This mirrors the hard-cutover
/// discipline from the Python SDK v0.1.5.
///
/// ## Usage
/// ```swift
/// let vad = FacadeVad(nativeRuntime: runtime)
/// let transitions = try await vad.detect(audio: pcmData, sampleRate: 16000)
/// for t in transitions {
///     print("\(t.kind) @ \(t.timestampMs)ms (conf=\(t.confidence))")
/// }
/// ```
///
/// `openSession` is not yet wired in the iOS FFI path — all calls return
/// ``OctomilError/runtimeUnavailable(reason:)`` until that work lands.
public final class FacadeVad: @unchecked Sendable {

    // MARK: - Dependencies

    private let nativeRuntimeProvider: @Sendable () async throws -> any NativeRuntime

    // MARK: - Init

    /// Create with a native runtime provider closure. The closure is
    /// evaluated lazily on each ``detect`` call.
    ///
    /// - Parameter nativeRuntimeProvider: Async closure that opens (or
    ///   returns a cached) ``NativeRuntime``. When the runtime library
    ///   is not installed the closure throws ``NativeRuntimeError`` with
    ///   ``NativeStatus/unsupported``, which the facade maps to
    ///   ``OctomilError/runtimeUnavailable(reason:)``.
    public init(
        nativeRuntimeProvider: @escaping @Sendable () async throws -> any NativeRuntime
    ) {
        self.nativeRuntimeProvider = nativeRuntimeProvider
    }

    // MARK: - detect

    /// Detect voice-activity transitions in a PCM audio clip.
    ///
    /// Submits `audio` as a single chunk to the runtime's
    /// ``audio.vad`` session and drains all ``vadTransition`` events
    /// until ``sessionCompleted``.
    ///
    /// - Parameters:
    ///   - audio: Raw PCM-f32-LE samples, mono, 16 kHz. Must be a
    ///     multiple of 4 bytes and contain no NaN/Inf values.
    ///   - sampleRate: Must be 16 000. Other values throw
    ///     ``OctomilError/invalidInput(reason:)``.
    /// - Returns: All ``VadTransition`` edges detected in the clip.
    ///   Empty array when no speech activity was found.
    /// - Throws: ``OctomilError/runtimeUnavailable(reason:)`` until
    ///   ``FFINativeRuntime/openSession(config:model:)`` is wired
    ///   for ``audio.vad``.
    public func detect(
        audio: Data,
        sampleRate: Int = 16000
    ) async throws -> [VadTransition] {
        guard sampleRate == 16000 else {
            throw OctomilError.invalidInput(
                reason: "audio.vad: sampleRate must be 16000 (silero VAD is mono-16kHz-only); got \(sampleRate)"
            )
        }
        guard !audio.isEmpty else {
            throw OctomilError.invalidInput(
                reason: "audio.vad: audio data must not be empty"
            )
        }
        guard audio.count % 4 == 0 else {
            throw OctomilError.invalidInput(
                reason: "audio.vad: PCM-f32 buffer length \(audio.count) is not a multiple of 4 bytes"
            )
        }

        let runtime: any NativeRuntime
        do {
            runtime = try await nativeRuntimeProvider()
        } catch let nre as NativeRuntimeError {
            throw OctomilError.runtimeUnavailable(
                reason: "audio.vad: native runtime unavailable — \(nre.message ?? "unknown")"
            )
        }

        // audio.vad is model-free: the runtime adapter resolves the
        // silero artifact from OCTOMIL_SILERO_VAD_MODEL internally.
        // No oct_model_t is opened or passed — mirrors Python's
        // open_session(capability="audio.vad") call.
        let sessionConfig = NativeSessionConfig(
            modelURI: "",
            capability: RuntimeCapability.audioVad.rawValue,
            locality: "on-device",
            policyPreset: "private",
            sampleRateIn: UInt32(sampleRate),
            priority: .foreground
        )

        let session: any NativeSession
        do {
            session = try await runtime.openSessionModelFree(config: sessionConfig)
        } catch let nre as NativeRuntimeError {
            throw nativeRuntimeErrorToOctomilError(nre, capability: "audio.vad", operation: "openSession")
        }

        defer {
            Task { await session.close() }
        }

        // Send audio chunk
        do {
            try await session.sendAudio(audio, sampleRate: UInt32(sampleRate), channels: 1)
        } catch let nre as NativeRuntimeError {
            throw nativeRuntimeErrorToOctomilError(nre, capability: "audio.vad", operation: "sendAudio")
        }

        // Drain transitions
        return try await drainVadTransitions(session: session)
    }

    // MARK: - Private helpers

    private func drainVadTransitions(session: any NativeSession) async throws -> [VadTransition] {
        var transitions: [VadTransition] = []
        let deadline = Date().addingTimeInterval(300)  // 5-minute deadline, mirrors Python

        while Date() < deadline {
            let event: NativeEvent?
            do {
                event = try await session.pollEvent(timeout: 0.2)
            } catch let nre as NativeRuntimeError {
                throw nativeRuntimeErrorToOctomilError(nre, capability: "audio.vad", operation: "pollEvent")
            }

            guard let ev = event else { continue }

            switch ev {
            case .sessionStarted:
                continue
            case .vadTransition(let payload, _):
                let kind: VadTransitionKind
                switch payload.transitionKind {
                case 1: kind = .speechStart
                case 2: kind = .speechEnd
                default: kind = .unknown
                }
                if kind != .unknown {
                    transitions.append(VadTransition(
                        kind: kind,
                        timestampMs: Int(payload.timestampMs),
                        confidence: payload.confidence
                    ))
                }
            case .error(let payload, _):
                throw OctomilError.inferenceFailed(
                    reason: "audio.vad: runtime error — \(payload.message) (code: \(payload.code))"
                )
            case .sessionCompleted(let payload, _):
                if payload.terminalStatus != .ok {
                    throw OctomilError.inferenceFailed(
                        reason: "audio.vad: session terminated with non-OK status: \(payload.terminalStatus)"
                    )
                }
                return transitions
            default:
                continue
            }
        }

        throw OctomilError.requestTimeout
    }
}

// MARK: - NativeRuntimeError → OctomilError mapping (audio capabilities)

/// Maps a ``NativeRuntimeError`` to ``OctomilError`` for audio facades.
/// ``unsupported`` maps to ``runtimeUnavailable`` per the fail-closed
/// audio-capability policy (mirrors Python's
/// `default_unsupported_code=OctomilErrorCode.RUNTIME_UNAVAILABLE`).
func nativeRuntimeErrorToOctomilError(
    _ nre: NativeRuntimeError,
    capability: String,
    operation: String
) -> OctomilError {
    let msg = nre.message ?? "unknown"
    switch nre.status {
    case .ok:
        return .inferenceFailed(reason: "\(capability) \(operation): unexpected OK status in error path")
    case .unsupported, .busy, .versionMismatch:
        return .runtimeUnavailable(
            reason: "\(capability): native runtime unavailable (\(operation)) — \(msg). " +
                "openSession for \(capability) will be wired in a future release."
        )
    case .invalidInput:
        return .invalidInput(reason: "\(capability) \(operation): \(msg)")
    case .notFound:
        return .modelNotFound(modelId: "\(capability): \(msg)")
    case .timeout:
        return .streamInterrupted(reason: "\(capability) \(operation) timed out: \(msg)")
    case .cancelled:
        return .cancelled
    case .internalError:
        return .inferenceFailed(reason: "\(capability) \(operation) internal error: \(msg)")
    }
}

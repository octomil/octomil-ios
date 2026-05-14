import Foundation

// MARK: - DiarizationSegment

/// One speaker-labelled segment returned by
/// ``FacadeDiarization/create(audio:sampleRate:)``.
///
/// Mirrors Python ``DiarizationSegment`` from
/// `octomil/runtime/native/diarization_backend.py`.
///
/// - ``startMs`` / ``endMs``: Millisecond offsets from the start of
///   the submitted audio clip.
/// - ``speakerID``: Numeric speaker index assigned by the runtime
///   (0-based, stable within a single call).
/// - ``speakerLabel``: Human-readable label (e.g. ``"SPEAKER_00"``).
public struct DiarizationSegment: Sendable {
    public let startMs: Int
    public let endMs: Int
    public let speakerID: Int
    public let speakerLabel: String

    public init(startMs: Int, endMs: Int, speakerID: Int, speakerLabel: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.speakerID = speakerID
        self.speakerLabel = speakerLabel
    }
}

// MARK: - FacadeDiarization

/// Public Swift facade for the ``audio.diarization`` capability.
///
/// Mirrors Python's
/// `octomil.audio.diarization.open_diarization_backend()` API from
/// `octomil/audio/diarization.py`.
///
/// The runtime runs pyannote-style speaker segmentation + sherpa-onnx
/// speaker embeddings under the hood; this facade owns the Swift
/// ergonomics only.
///
/// ## Fail-closed contract
/// Hard-cut to native. No Python / cloud fallback. When the runtime
/// does not advertise ``audio.diarization``, every call throws
/// ``OctomilError/runtimeUnavailable(reason:)``.
///
/// ## Usage
/// ```swift
/// let diar = FacadeDiarization(nativeRuntime: runtime)
/// let segments = try await diar.create(audio: pcmData, sampleRate: 16000)
/// for seg in segments {
///     print("\(seg.speakerLabel): \(seg.startMs)–\(seg.endMs)ms")
/// }
/// ```
///
/// When ``liboctomil_runtime.dylib`` is loaded and the sherpa-onnx
/// diarization model artifacts are present, calls route through the FFI
/// session lifecycle and return real segments. When the dylib is absent,
/// every call throws ``OctomilError/runtimeUnavailable(reason:)``.
public final class FacadeDiarization: @unchecked Sendable {

    // MARK: - Dependencies

    private let nativeRuntimeProvider: @Sendable () async throws -> any NativeRuntime

    // MARK: - Init

    /// Create with a native runtime provider closure.
    public init(
        nativeRuntimeProvider: @escaping @Sendable () async throws -> any NativeRuntime
    ) {
        self.nativeRuntimeProvider = nativeRuntimeProvider
    }

    // MARK: - create

    /// Diarize an audio clip and return speaker segments.
    ///
    /// Submits the audio as a single chunk to the runtime's
    /// ``audio.diarization`` session, drains all
    /// ``diarizationSegment`` events, and returns them in
    /// chronological order.
    ///
    /// ``audio.diarization`` is a model-free capability: the runtime
    /// adapter resolves its artifact from env vars. No model URI is
    /// passed to the session; this mirrors Python's
    /// ``open_session(capability="audio.diarization")`` contract.
    ///
    /// - Parameters:
    ///   - audio: Raw PCM-f32-LE bytes, mono, 16 kHz. Non-empty,
    ///     length must be a multiple of 4 bytes.
    ///   - sampleRate: Must be 16 000.
    /// - Returns: Speaker segments in order of appearance.
    /// - Throws: ``OctomilError/runtimeUnavailable(reason:)`` when
    ///   ``liboctomil_runtime.dylib`` is unavailable or the sherpa-onnx
    ///   diarization model artifacts are not present.
    public func create(
        audio: Data,
        sampleRate: Int = 16000
    ) async throws -> [DiarizationSegment] {
        guard sampleRate == 16000 else {
            throw OctomilError.invalidInput(
                reason: "audio.diarization: sampleRate must be 16000; got \(sampleRate)"
            )
        }
        guard !audio.isEmpty else {
            throw OctomilError.invalidInput(
                reason: "audio.diarization: audio data must not be empty"
            )
        }
        guard audio.count % 4 == 0 else {
            throw OctomilError.invalidInput(
                reason: "audio.diarization: PCM-f32 buffer length \(audio.count) is not a multiple of 4 bytes"
            )
        }

        let runtime: any NativeRuntime
        do {
            runtime = try await nativeRuntimeProvider()
        } catch let nre as NativeRuntimeError {
            throw OctomilError.runtimeUnavailable(
                reason: "audio.diarization: native runtime unavailable — \(nre.message ?? "unknown")"
            )
        }

        // audio.diarization is model-free: the runtime adapter resolves
        // the sherpa-onnx diarization artifact from its env vars
        // internally. No oct_model_t is opened or passed — mirrors
        // Python's open_session(capability="audio.diarization") call.
        let sessionConfig = NativeSessionConfig(
            modelURI: "",
            capability: RuntimeCapability.audioDiarization.rawValue,
            locality: "on-device",
            policyPreset: "private",
            sampleRateIn: UInt32(sampleRate),
            priority: .foreground
        )

        let session: any NativeSession
        do {
            session = try await runtime.openSessionModelFree(config: sessionConfig)
        } catch let nre as NativeRuntimeError {
            throw nativeRuntimeErrorToOctomilError(
                nre, capability: "audio.diarization", operation: "openSession"
            )
        }

        defer {
            Task { await session.close() }
        }

        do {
            try await session.sendAudio(audio, sampleRate: UInt32(sampleRate), channels: 1)
        } catch let nre as NativeRuntimeError {
            throw nativeRuntimeErrorToOctomilError(
                nre, capability: "audio.diarization", operation: "sendAudio"
            )
        }

        return try await drainSegments(session: session)
    }

    // MARK: - Private helpers

    private func drainSegments(session: any NativeSession) async throws -> [DiarizationSegment] {
        var segments: [DiarizationSegment] = []
        let deadline = Date().addingTimeInterval(300)

        while Date() < deadline {
            let event: NativeEvent?
            do {
                event = try await session.pollEvent(timeout: 0.2)
            } catch let nre as NativeRuntimeError {
                throw nativeRuntimeErrorToOctomilError(
                    nre, capability: "audio.diarization", operation: "pollEvent"
                )
            }

            guard let ev = event else { continue }

            switch ev {
            case .sessionStarted:
                continue
            case .diarizationSegment(let payload, _):
                segments.append(DiarizationSegment(
                    startMs: Int(payload.startMs),
                    endMs: Int(payload.endMs),
                    speakerID: Int(payload.speakerID),
                    speakerLabel: payload.speakerLabel
                ))
            case .error(let payload, _):
                throw OctomilError.inferenceFailed(
                    reason: "audio.diarization: runtime error — \(payload.message) (code: \(payload.code))"
                )
            case .sessionCompleted(let payload, _):
                if payload.terminalStatus != .ok {
                    throw OctomilError.inferenceFailed(
                        reason: "audio.diarization: session terminated with non-OK status: \(payload.terminalStatus)"
                    )
                }
                return segments
            default:
                continue
            }
        }

        throw OctomilError.requestTimeout
    }
}

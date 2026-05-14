import Foundation

// MARK: - FacadeSpeakerEmbedding

/// Public Swift facade for the ``audio.speaker.embedding`` capability.
///
/// Mirrors Python's `octomil.audio.speaker_embedding.open_speaker_embedding_backend()`
/// API from `octomil/audio/speaker_embedding.py`.
///
/// Returns an L2-normalized speaker embedding vector (typically 512 floats
/// from the sherpa-onnx ERes2NetV2 base model). Callers MUST NOT hardcode
/// the dimension — read it from the returned array's count, since future
/// model updates may change it.
///
/// ## Fail-closed contract
/// Hard-cut to native. No Python / cloud fallback. When the runtime does
/// not advertise ``audio.speaker.embedding`` (missing
/// `OCTOMIL_SHERPA_SPEAKER_MODEL`, digest mismatch, or engine not
/// compiled in), every call throws
/// ``OctomilError/runtimeUnavailable(reason:)``.
///
/// ## Usage
/// ```swift
/// let se = FacadeSpeakerEmbedding(nativeRuntime: runtime)
/// let vecA = try await se.create(audio: clipA, sampleRate: 16000)
/// let vecB = try await se.create(audio: clipB, sampleRate: 16000)
/// // vecA and vecB are L2-normalized; cosine = dot product.
/// ```
///
/// When ``liboctomil_runtime.dylib`` is loaded and
/// ``OCTOMIL_SHERPA_SPEAKER_MODEL`` is set, calls route through the FFI
/// session lifecycle and return real embedding vectors. When the dylib is
/// absent, every call throws ``OctomilError/runtimeUnavailable(reason:)``.
public final class FacadeSpeakerEmbedding: @unchecked Sendable {

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

    /// Extract a speaker embedding vector from an audio clip.
    ///
    /// Opens a single ``audio.speaker.embedding`` session, sends the
    /// audio, drains the ``embeddingVector`` event, and closes the
    /// session. One call per utterance — mirrors Python's
    /// `NativeSpeakerEmbeddingBackend.embed(clip)`.
    ///
    /// - Parameters:
    ///   - audio: Raw PCM-f32-LE bytes, mono, 16 kHz. Must be
    ///     non-empty and a multiple of 4 bytes.
    ///   - sampleRate: Must be 16 000.
    ///   - model: Optional model identifier hint (default
    ///     ``"sherpa-eres2netv2-base"``). Passed to the runtime via
    ///     `modelURI`; the runtime rejects unknown models with
    ///     ``NativeStatus/unsupported``.
    /// - Returns: L2-normalized embedding vector as `[Float]`.
    /// - Throws: ``OctomilError/runtimeUnavailable(reason:)`` when
    ///   ``liboctomil_runtime.dylib`` is unavailable or
    ///   ``OCTOMIL_SHERPA_SPEAKER_MODEL`` is not set.
    public func create(
        audio: Data,
        sampleRate: Int = 16000,
        model: String = "sherpa-eres2netv2-base"
    ) async throws -> [Float] {
        guard sampleRate == 16000 else {
            throw OctomilError.invalidInput(
                reason: "audio.speaker.embedding: sampleRate must be 16000; got \(sampleRate)"
            )
        }
        guard !audio.isEmpty else {
            throw OctomilError.invalidInput(
                reason: "audio.speaker.embedding: audio data must not be empty"
            )
        }
        guard audio.count % 4 == 0 else {
            throw OctomilError.invalidInput(
                reason: "audio.speaker.embedding: PCM-f32 buffer length \(audio.count) is not a multiple of 4 bytes"
            )
        }

        let runtime: any NativeRuntime
        do {
            runtime = try await nativeRuntimeProvider()
        } catch let nre as NativeRuntimeError {
            throw OctomilError.runtimeUnavailable(
                reason: "audio.speaker.embedding: native runtime unavailable — \(nre.message ?? "unknown")"
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
            throw nativeRuntimeErrorToOctomilError(nre, capability: "audio.speaker.embedding", operation: "openModel")
        }

        let sessionConfig = NativeSessionConfig(
            modelURI: model,
            capability: RuntimeCapability.audioSpeakerEmbedding.rawValue,
            locality: "on-device",
            policyPreset: "private",
            sampleRateIn: UInt32(sampleRate),
            priority: .foreground
        )

        let session: any NativeSession
        do {
            session = try await runtime.openSession(config: sessionConfig, model: nativeModel)
        } catch let nre as NativeRuntimeError {
            try? await nativeModel.close()
            throw nativeRuntimeErrorToOctomilError(
                nre, capability: "audio.speaker.embedding", operation: "openSession"
            )
        }

        defer {
            Task { await session.close() }
            Task { try? await nativeModel.close() }
        }

        do {
            try await session.sendAudio(audio, sampleRate: UInt32(sampleRate), channels: 1)
        } catch let nre as NativeRuntimeError {
            throw nativeRuntimeErrorToOctomilError(
                nre, capability: "audio.speaker.embedding", operation: "sendAudio"
            )
        }

        return try await drainEmbedding(session: session)
    }

    // MARK: - Private helpers

    private func drainEmbedding(session: any NativeSession) async throws -> [Float] {
        let deadline = Date().addingTimeInterval(300)

        while Date() < deadline {
            let event: NativeEvent?
            do {
                event = try await session.pollEvent(timeout: 0.2)
            } catch let nre as NativeRuntimeError {
                throw nativeRuntimeErrorToOctomilError(
                    nre, capability: "audio.speaker.embedding", operation: "pollEvent"
                )
            }

            guard let ev = event else { continue }

            switch ev {
            case .sessionStarted:
                continue
            case .embeddingVector(let payload, _):
                return payload.values
            case .error(let payload, _):
                throw OctomilError.inferenceFailed(
                    reason: "audio.speaker.embedding: runtime error — \(payload.message) (code: \(payload.code))"
                )
            case .sessionCompleted(let payload, _):
                if payload.terminalStatus != .ok {
                    throw OctomilError.inferenceFailed(
                        reason: "audio.speaker.embedding: session terminated with non-OK status: \(payload.terminalStatus)"
                    )
                }
                // sessionCompleted without an embeddingVector is an
                // inference error — the runtime must emit the vector
                // before SESSION_COMPLETED.
                throw OctomilError.inferenceFailed(
                    reason: "audio.speaker.embedding: session completed without an embedding vector"
                )
            default:
                continue
            }
        }

        throw OctomilError.requestTimeout
    }
}

#if canImport(sherpa_onnx)
import Foundation
import Octomil

// MARK: - Runtime Evidence

extension InstalledRuntime {

    /// Create runtime evidence for a locally-available sherpa-onnx TTS model.
    ///
    /// Call this only when a concrete sherpa-onnx TTS model directory exists
    /// on disk (Kokoro voices.bin or VITS model.onnx). Framework availability
    /// alone is not sufficient evidence.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "kokoro-82m", "piper-en-amy").
    ///   - artifactDigest: SHA-256 hex digest of the model directory, if known.
    /// - Returns: An ``InstalledRuntime`` with model evidence metadata.
    public static func sherpaTtsEvidence(
        model: String,
        artifactDigest: String? = nil
    ) -> InstalledRuntime {
        modelCapable(
            engine: "sherpa-onnx",
            model: model,
            capabilities: ["tts"],
            artifactDigest: artifactDigest,
            artifactFormat: "onnx"
        )
    }
}

// MARK: - Notes
//
// Unlike the streaming-ASR sibling (OctomilRuntimeSherpa), TTS does NOT
// plug into ``EngineRegistry``: that registry's factory contract returns
// ``StreamingInferenceEngine``, which is shaped for token-streaming text
// inference, not single-shot synthesis. TTS callers construct
// ``SherpaTtsEngine(modelPath:)`` directly and call ``synthesize(text:...)``,
// the same way ``SherpaTtsRuntime`` works on Android.
//
// If a streaming TTS surface ships in the future (token/sample streaming
// to a `<audio>`-style consumer), it will land as a new TTS-specific
// registry seam, not by widening ``EngineRegistry``.
#endif

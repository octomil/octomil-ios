#if canImport(sherpa_onnx)
import Foundation
import Octomil

extension EngineRegistry {

    /// Register the sherpa-onnx TTS engine for on-device speech synthesis.
    ///
    /// Call once during SDK init when the optional `OctomilRuntimeSherpaTTS`
    /// target is linked. Idempotent — safe to call multiple times.
    public func registerSherpaTTS() {
        // No streaming TTS surface yet; the engine vends a single-shot
        // synthesize() per request. The audio modality is shared with
        // sherpa ASR (via OctomilRuntimeSherpa), so we register under a
        // distinct .sherpaTTS engine key when available, falling back to
        // .sherpa otherwise.
        register(modality: .audio, engine: .sherpa) { url in
            SherpaTtsAudioRuntimeAdapter(modelPath: url)
        }
    }
}

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

// MARK: - Runtime Adapter

/// Thin adapter exposing ``SherpaTtsEngine`` to the runtime registry.
final class SherpaTtsAudioRuntimeAdapter: @unchecked Sendable {
    private let modelPath: URL
    private var engine: SherpaTtsEngine?

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    /// Lazily load the engine. Returns the cached instance after the first call.
    func ensureLoaded() throws -> SherpaTtsEngine {
        if let engine { return engine }
        let loaded = try SherpaTtsEngine(modelPath: modelPath)
        self.engine = loaded
        return loaded
    }
}
#endif

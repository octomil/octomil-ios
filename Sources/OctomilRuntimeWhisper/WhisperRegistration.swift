import Foundation
import Octomil

extension EngineRegistry {

    /// Register the whisper.cpp batch engine for audio transcription.
    ///
    /// Registers under `(modality: .audio, engine: .whisper)` so callers can
    /// explicitly request whisper for batch transcription.
    public func registerWhisper() {
        register(modality: .audio, engine: .whisper) { url in
            WhisperBatchEngine(modelPath: url)
        }
    }
}

// MARK: - Runtime Evidence

extension InstalledRuntime {

    /// Create runtime evidence for a locally-available whisper.cpp model.
    ///
    /// Call this only when a concrete whisper model file exists on disk.
    /// Framework availability alone is not sufficient evidence.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "whisper-base", "whisper-large-v3").
    ///   - artifactDigest: SHA-256 hex digest of the model file, if known.
    /// - Returns: An ``InstalledRuntime`` with model evidence metadata.
    public static func whisperEvidence(
        model: String,
        artifactDigest: String? = nil
    ) -> InstalledRuntime {
        modelCapable(
            engine: "whisper.cpp",
            model: model,
            capabilities: ["audio_transcription"],
            accelerator: "metal",
            artifactDigest: artifactDigest,
            artifactFormat: "gguf"
        )
    }
}

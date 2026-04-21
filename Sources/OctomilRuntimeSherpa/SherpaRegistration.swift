#if canImport(sherpa_onnx)
import Foundation
import Octomil

extension EngineRegistry {

    /// Register the sherpa-onnx streaming engine for audio transcription.
    ///
    /// Registers as the default audio engine (no specific engine key), so any
    /// `resolve(modality: .audio, ...)` call will use sherpa-onnx unless a more
    /// specific engine is registered.
    public func registerSherpa() {
        register(modality: .audio, engine: .sherpa) { url in
            SherpaStreamingEngine(modelPath: url)
        }

        // Also register as the default audio engine
        register(modality: .audio) { url in
            SherpaStreamingEngine(modelPath: url)
        }

        // Register live transcriber for real-time microphone streaming
        LiveTranscriberFactory.shared.register(engine: "sherpa") { url in
            SherpaLiveTranscriber(modelPath: url)
        }
        LiveTranscriberFactory.shared.register(engine: "sherpa-onnx") { url in
            SherpaLiveTranscriber(modelPath: url)
        }
    }
}

// MARK: - Runtime Evidence

extension InstalledRuntime {

    /// Create runtime evidence for a locally-available sherpa-onnx ASR model.
    ///
    /// Call this only when a concrete sherpa-onnx model directory exists on disk.
    /// Framework availability alone is not sufficient evidence.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "sherpa-streaming-zipformer").
    ///   - artifactDigest: SHA-256 hex digest of the model directory, if known.
    /// - Returns: An ``InstalledRuntime`` with model evidence metadata.
    public static func sherpaEvidence(
        model: String,
        artifactDigest: String? = nil
    ) -> InstalledRuntime {
        modelCapable(
            engine: "whisper.cpp",
            model: model,
            capabilities: ["audio_transcription"],
            artifactDigest: artifactDigest,
            artifactFormat: "onnx"
        )
    }
}
#endif

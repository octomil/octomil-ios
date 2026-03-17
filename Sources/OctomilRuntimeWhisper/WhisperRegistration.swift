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

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
    }
}

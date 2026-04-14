import Foundation
import Octomil

extension EngineRegistry {

    /// Register the llama.cpp engine for text generation.
    ///
    /// After calling this method, `resolve(modality: .text, engine: .llamaCpp, ...)`
    /// produces a ``LlamaCppEngine`` that loads the GGUF model from the given URL.
    public func registerLlamaCpp() {
        register(modality: .text, engine: .llamaCpp) { url in
            LlamaCppEngine(modelPath: url)
        }
    }
}

// MARK: - Runtime Evidence

extension InstalledRuntime {

    /// Create runtime evidence for a locally-available llama.cpp GGUF model.
    ///
    /// Call this only when a concrete GGUF artifact exists on disk.
    /// Framework availability alone is not sufficient evidence.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "llama-8b", "phi-3").
    ///   - artifactDigest: SHA-256 hex digest of the GGUF file, if known.
    /// - Returns: An ``InstalledRuntime`` with model evidence metadata.
    public static func llamaCppEvidence(
        model: String,
        artifactDigest: String? = nil
    ) -> InstalledRuntime {
        modelCapable(
            engine: "llama.cpp",
            model: model,
            capabilities: ["text"],
            accelerator: "metal",
            artifactDigest: artifactDigest,
            artifactFormat: "gguf"
        )
    }
}

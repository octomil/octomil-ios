import Foundation

/// Selects the best engine for a given model, considering overrides, benchmarks, and defaults.
///
/// Resolution order:
/// 1. Server override for this model ID
/// 2. Server override for `"*"` (global)
/// 3. Local override for this model ID
/// 4. Local override for `"*"` (global)
/// 5. Persisted benchmark winner for this model + device
/// 6. URL-inferred engine (file extension)
/// 7. Registry default for modality
public actor RuntimeSelector {

    /// Shared singleton instance.
    public static let shared = RuntimeSelector()

    /// Server-pushed overrides. Key = model ID or `"*"` for global fallback.
    private var serverOverrides: [String: Engine] = [:]

    /// Local configuration overrides. Key = model ID or `"*"` for global fallback.
    private var localOverrides: [String: Engine] = [:]

    // MARK: - Configuration

    /// Apply server-side engine overrides (from ControlSync).
    public func setServerOverrides(_ overrides: [String: Engine]) {
        serverOverrides = overrides
    }

    /// Apply local engine overrides (from OctomilConfiguration).
    public func setLocalOverrides(_ overrides: [String: Engine]) {
        localOverrides = overrides
    }

    // MARK: - Selection

    /// Select the best engine for a given model.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier (e.g. "whisper-tiny", "llama-3.2-1b").
    ///   - modality: The output modality.
    ///   - modelURL: URL of the model file/directory, used for URL-based engine inference.
    ///   - registry: The engine registry to resolve against. Defaults to shared.
    /// - Returns: A configured ``StreamingInferenceEngine``.
    /// - Throws: ``EngineResolutionError`` if no matching factory is found.
    public func selectEngine(
        modelId: String,
        modality: Modality,
        modelURL: URL,
        registry: EngineRegistry = .shared
    ) throws -> StreamingInferenceEngine {
        // 1-2. Server overrides (model-specific, then global)
        if let engine = serverOverrides[modelId] ?? serverOverrides["*"] {
            return try registry.resolve(modality: modality, engine: engine, modelURL: modelURL)
        }

        // 3-4. Local overrides (model-specific, then global)
        if let engine = localOverrides[modelId] ?? localOverrides["*"] {
            return try registry.resolve(modality: modality, engine: engine, modelURL: modelURL)
        }

        // 5. Persisted benchmark winner
        if let engine = BenchmarkStore.shared.winner(modelId: modelId, modelURL: modelURL) {
            return try registry.resolve(modality: modality, engine: engine, modelURL: modelURL)
        }

        // 6-7. URL inference + registry default
        let inferred = EngineRegistry.engineFromURL(modelURL)
        return try registry.resolve(modality: modality, engine: inferred, modelURL: modelURL)
    }
}

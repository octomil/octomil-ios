import Foundation

// MARK: - RuntimeEvidenceMetadataKey

/// Well-known metadata keys for ``InstalledRuntime`` evidence.
///
/// These keys are used by ``InstalledRuntime.modelCapable(...)`` and consumed
/// by ``RuntimePlanner.supportsLocalDefault(_:model:capability:)`` during
/// local resolution. Using consistent keys across all engine modules
/// ensures the planner can match model/capability pairs reliably.
public enum RuntimeEvidenceMetadataKey {
    /// Comma-separated model IDs this runtime can serve (e.g. "llama-8b,gemma-2b").
    public static let models = "models"
    /// Comma-separated capabilities (e.g. "text", "audio_transcription").
    public static let capabilities = "capabilities"
    /// SHA-256 hex digest of the local artifact, if known.
    public static let artifactDigest = "artifact_digest"
    /// Artifact format string (e.g. "gguf", "mlx", "coreml").
    public static let artifactFormat = "artifact_format"
}

// MARK: - InstalledRuntime + Model Evidence

extension InstalledRuntime {

    /// Create an ``InstalledRuntime`` that declares support for a specific
    /// model and capability, backed by a real local artifact.
    ///
    /// This is the primary way engine modules (OctomilMLX, OctomilRuntimeLlama,
    /// OctomilRuntimeSherpa, etc.) communicate concrete model availability to
    /// the ``RuntimePlanner``. Framework availability alone is never sufficient;
    /// evidence must be attached only when a local artifact path or model ID is
    /// known.
    ///
    /// - Parameters:
    ///   - engine: Raw engine name (will be canonicalized via ``RuntimeEngineID``).
    ///   - model: Model identifier (e.g. "llama-8b", "whisper-base").
    ///   - capabilities: Capabilities the model supports (e.g. ["text"], ["audio_transcription"]).
    ///   - version: Engine version string, if known.
    ///   - accelerator: Hardware accelerator (e.g. "metal", "ane").
    ///   - artifactDigest: SHA-256 hex digest of the local artifact, if known.
    ///   - artifactFormat: Format of the local artifact (e.g. "gguf", "mlx").
    /// - Returns: A fully-qualified ``InstalledRuntime`` with model evidence metadata.
    public static func modelCapable(
        engine: String,
        model: String,
        capabilities: [String],
        version: String? = nil,
        accelerator: String? = nil,
        artifactDigest: String? = nil,
        artifactFormat: String? = nil
    ) -> InstalledRuntime {
        var metadata: [String: String] = [
            RuntimeEvidenceMetadataKey.models: model.lowercased(),
            RuntimeEvidenceMetadataKey.capabilities: capabilities
                .map { $0.lowercased() }
                .joined(separator: ","),
        ]
        if let digest = artifactDigest {
            metadata[RuntimeEvidenceMetadataKey.artifactDigest] = digest
        }
        if let format = artifactFormat {
            metadata[RuntimeEvidenceMetadataKey.artifactFormat] = format.lowercased()
        }

        return InstalledRuntime(
            engine: engine,
            version: version,
            available: true,
            accelerator: accelerator,
            metadata: metadata
        )
    }
}

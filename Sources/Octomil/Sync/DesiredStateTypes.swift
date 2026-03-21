import Foundation

// MARK: - Desired State Model Types (contract 1.12.0)

/// Engine policy specifying which runtime engines are allowed/forced for a model.
public struct EnginePolicy: Codable, Sendable {
    public let allowed: [String]
    public let forced: String?
}

/// Artifact manifest embedded in a desired model entry.
///
/// Contains the artifact identifier and metadata needed to fetch
/// the full file manifest via ``GET /artifacts/{artifactId}/manifest``.
public struct ArtifactManifest: Codable, Sendable {
    public let artifactId: String
    public let modelId: String
    public let version: String
    public let totalBytes: Int64?
}

/// A single model entry within the desired state response.
///
/// Matches the server's contract 1.12.0 schema (camelCase JSON).
/// The SDK uses ``artifactManifest.artifactId`` to fetch the full
/// file manifest and download URLs from the artifact endpoints.
public struct DesiredModelEntry: Codable, Sendable {
    public let modelId: String
    public let desiredVersion: String
    public let deliveryMode: String
    public let activationPolicy: String
    public let enginePolicy: EnginePolicy?
    public let artifactManifest: ArtifactManifest?
    public let rolloutId: String?

    public init(
        modelId: String,
        desiredVersion: String,
        deliveryMode: String = "managed",
        activationPolicy: String = "immediate",
        enginePolicy: EnginePolicy? = nil,
        artifactManifest: ArtifactManifest? = nil,
        rolloutId: String? = nil
    ) {
        self.modelId = modelId
        self.desiredVersion = desiredVersion
        self.deliveryMode = deliveryMode
        self.activationPolicy = activationPolicy
        self.enginePolicy = enginePolicy
        self.artifactManifest = artifactManifest
        self.rolloutId = rolloutId
    }
}

// MARK: - Reconcile Action

/// An action determined by comparing desired state to local state.
public enum ReconcileAction: Sendable {
    /// Download and install a new artifact.
    case download(DesiredModelEntry)
    /// Activate a staged artifact.
    case activate(modelId: String, version: String)
    /// Remove a garbage-collectable artifact.
    case remove(artifactId: String)
    /// No action needed — model is up to date and active.
    case upToDate(modelId: String)
}

// MARK: - Artifact Endpoint Types

/// A single file within an artifact manifest.
public struct ArtifactFileInfo: Codable, Sendable {
    public let path: String
    public let sizeBytes: Int64
    public let sha256: String

    enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size_bytes"
        case sha256
    }
}

/// Response from ``GET /api/v1/artifacts/{id}/manifest``.
public struct ArtifactManifestResponse: Codable, Sendable {
    public let artifactId: String
    public let modelId: String
    public let version: String
    public let totalBytes: Int64
    public let files: [ArtifactFileInfo]

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case modelId = "model_id"
        case version
        case totalBytes = "total_bytes"
        case files
    }
}

/// Request body for ``POST /api/v1/artifacts/{id}/download-urls``.
public struct DownloadUrlsRequest: Codable, Sendable {
    public let files: [String]
}

/// A single file download URL.
public struct FileDownloadUrl: Codable, Sendable {
    public let path: String
    public let url: String
}

/// Response from ``POST /api/v1/artifacts/{id}/download-urls``.
public struct DownloadUrlsResponse: Codable, Sendable {
    public let artifactId: String
    public let urls: [FileDownloadUrl]

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case urls
    }
}

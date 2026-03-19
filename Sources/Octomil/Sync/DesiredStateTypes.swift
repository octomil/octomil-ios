import Foundation

// MARK: - Desired State Model Types

/// Activation policy for a model artifact, as specified by the server.
public enum ActivationPolicy: String, Codable, Sendable {
    /// Activate immediately after download and verification.
    case immediate
    /// Activate on the next app launch.
    case nextLaunch = "next_launch"
    /// Require explicit activation call from the host app.
    case manual
    /// Activate when the device is idle (low CPU, screen off).
    case whenIdle = "when_idle"
}

/// A single model entry within the desired state response.
public struct DesiredModelEntry: Codable, Sendable {
    public let modelId: String
    public let modelVersion: String
    public let artifactVersion: String
    public let artifactId: String
    public let downloadUrl: String
    public let checksum: String
    public let fileSize: Int64
    public let activationPolicy: ActivationPolicy

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case modelVersion = "model_version"
        case artifactVersion = "artifact_version"
        case artifactId = "artifact_id"
        case downloadUrl = "download_url"
        case checksum
        case fileSize = "file_size"
        case activationPolicy = "activation_policy"
    }

    public init(
        modelId: String,
        modelVersion: String,
        artifactVersion: String,
        artifactId: String,
        downloadUrl: String,
        checksum: String,
        fileSize: Int64,
        activationPolicy: ActivationPolicy = .immediate
    ) {
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.artifactVersion = artifactVersion
        self.artifactId = artifactId
        self.downloadUrl = downloadUrl
        self.checksum = checksum
        self.fileSize = fileSize
        self.activationPolicy = activationPolicy
    }
}

// MARK: - Reconcile Action

/// An action determined by comparing desired state to local state.
public enum ReconcileAction: Sendable {
    /// Download and install a new artifact.
    case download(DesiredModelEntry)
    /// Activate a staged artifact.
    case activate(modelId: String, artifactVersion: String)
    /// Remove a garbage-collectable artifact.
    case remove(artifactId: String)
    /// No action needed — model is up to date and active.
    case upToDate(modelId: String)
}

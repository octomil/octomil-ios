import Foundation

// MARK: - LocalAssetStatus

/// Describes the readiness of a local model asset.
///
/// Use this to determine what action is needed before inference can proceed.
/// The lifecycle is idempotent: calling ``ModelManager/checkAssetStatus(modelId:version:)``
/// a second time after a successful download returns `.ready` without re-downloading.
///
/// - `.ready` — The model is cached locally, verified, and ready for inference.
///   Second-run behavior: returns immediately from cache.
/// - `.downloadRequired` — The model is not cached. The URL and size are provided
///   so the caller can display download UI or decide whether to proceed.
/// - `.preparing` — A download or compilation is in progress for this model.
/// - `.unavailable` — The model cannot be made available locally (e.g. no network,
///   model not found on server, unsupported format).
public enum LocalAssetStatus: Sendable {
    /// Model is cached and ready for inference.
    /// The associated URL points to the compiled model on disk.
    case ready(localURL: URL)

    /// Model must be downloaded before use.
    /// `url` is the download source; `sizeBytes` is the expected file size.
    case downloadRequired(url: URL, sizeBytes: Int64)

    /// A download or compilation is currently in progress.
    /// `progress` is 0.0–1.0 when known.
    case preparing(progress: Double?)

    /// The model cannot be prepared locally.
    /// `reason` is a human-readable, actionable explanation.
    case unavailable(reason: String)
}

// MARK: - Convenience accessors

extension LocalAssetStatus {

    /// Whether the model is ready for inference without any further work.
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Whether a download is needed before inference.
    public var needsDownload: Bool {
        if case .downloadRequired = self { return true }
        return false
    }

    /// Whether work is currently in progress to prepare this model.
    public var isPreparing: Bool {
        if case .preparing = self { return true }
        return false
    }

    /// The local file URL, if the model is ready. `nil` otherwise.
    public var localURL: URL? {
        if case .ready(let url) = self { return url }
        return nil
    }

    /// Human-readable description for logging and debugging.
    public var statusDescription: String {
        switch self {
        case .ready(let url):
            return "Ready at \(url.lastPathComponent)"
        case .downloadRequired(_, let size):
            let mb = Double(size) / (1024 * 1024)
            return String(format: "Download required (%.1f MB)", mb)
        case .preparing(let progress):
            if let p = progress {
                return String(format: "Preparing (%.0f%%)", p * 100)
            }
            return "Preparing..."
        case .unavailable(let reason):
            return "Unavailable: \(reason)"
        }
    }
}

// Auto-generated from octomil-contracts. Do not edit.

public enum ArtifactStatus: String, Codable, Sendable {
    case none = "none"
    case discovered = "discovered"
    case downloading = "downloading"
    case downloadedPartial = "downloaded_partial"
    case verifying = "verifying"
    case verified = "verified"
    case staged = "staged"
    case warming = "warming"
    case active = "active"
    case drainingOld = "draining_old"
    case finalized = "finalized"
    case gcEligible = "gc_eligible"
    case paused = "paused"
    case failedRetryable = "failed_retryable"
    case failedCorrupt = "failed_corrupt"
    case failedHealthcheck = "failed_healthcheck"
    case rollbackPending = "rollback_pending"
}

// Auto-generated from octomil-contracts. Do not edit.

public enum TrainingJobState: String, Codable, Sendable {
    case new = "new"
    case eligible = "eligible"
    case queued = "queued"
    case preparingData = "preparing_data"
    case waitingForResources = "waiting_for_resources"
    case training = "training"
    case checkpointing = "checkpointing"
    case evaluating = "evaluating"
    case candidateReady = "candidate_ready"
    case staged = "staged"
    case activating = "activating"
    case active = "active"
    case completed = "completed"
    case blockedPolicy = "blocked_policy"
    case paused = "paused"
    case failedRetryable = "failed_retryable"
    case failedFatal = "failed_fatal"
    case rejected = "rejected"
    case rollback = "rollback"
    case superseded = "superseded"
}

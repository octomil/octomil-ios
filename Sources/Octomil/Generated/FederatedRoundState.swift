// Auto-generated from octomil-contracts. Do not edit.

public enum FederatedRoundState: String, Codable, Sendable {
    case draft = "draft"
    case scheduled = "scheduled"
    case open = "open"
    case acceptingParticipants = "accepting_participants"
    case trainingInProgress = "training_in_progress"
    case aggregating = "aggregating"
    case validating = "validating"
    case publishing = "publishing"
    case published = "published"
    case closed = "closed"
    case cancelled = "cancelled"
    case failedValidation = "failed_validation"
    case insufficientUpdates = "insufficient_updates"
    case partialPublish = "partial_publish"
}

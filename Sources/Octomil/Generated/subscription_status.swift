// Auto-generated from octomil-contracts. Do not edit.

public enum SubscriptionStatus: String, Codable, Sendable {
    case active = "active"
    case pastDue = "past_due"
    case canceled = "canceled"
    case trialing = "trialing"
    case incomplete = "incomplete"
    case incompleteExpired = "incomplete_expired"
    case unpaid = "unpaid"
    case paused = "paused"
}

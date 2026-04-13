// Auto-generated from octomil-contracts. Do not edit.

public enum AdapterActivationState: String, Codable, Sendable {
    case none = "none"
    case staged = "staged"
    case warming = "warming"
    case shadow = "shadow"
    case active = "active"
    case drainingOld = "draining_old"
    case finalized = "finalized"
    case failedHealthcheck = "failed_healthcheck"
    case rejected = "rejected"
    case rollbackPending = "rollback_pending"
}

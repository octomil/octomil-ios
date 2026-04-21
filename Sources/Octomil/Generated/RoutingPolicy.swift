// Auto-generated from octomil-contracts. Do not edit.

public enum ContractRoutingPolicy: String, Codable, Sendable {
    case `private` = "private"
    case localOnly = "local_only"
    case localFirst = "local_first"
    case cloudFirst = "cloud_first"
    case cloudOnly = "cloud_only"
    case performanceFirst = "performance_first"
    case auto = "auto"
}

import Foundation

/// ADVANCED — MAY: Inference routing policy.
///
/// This is an optional advanced feature for hybrid local/cloud deployments.
/// Most applications use a single runtime and do not need routing policies.
///
/// Policy governing whether inference runs locally, in the cloud, or automatically.
public enum InferenceRoutingPolicy: Sendable {
    case auto(preferLocal: Bool = true, maxLatencyMs: Int? = nil, fallback: String = "cloud")
    case localOnly
    case cloudOnly

    /// Parse a routing policy from request metadata key-value pairs.
    public static func fromMetadata(_ metadata: [String: String]?) -> InferenceRoutingPolicy? {
        guard let metadata = metadata else { return nil }
        switch metadata["routing.policy"] {
        case "local_only": return .localOnly
        case "cloud_only": return .cloudOnly
        case "auto":
            return .auto(
                preferLocal: metadata["routing.prefer_local"] != "false",
                maxLatencyMs: metadata["routing.max_latency_ms"].flatMap(Int.init),
                fallback: metadata["routing.fallback"] ?? "cloud"
            )
        default: return nil
        }
    }
}

import Foundation

// MARK: - PlannerRoutingDefaults

/// Determines the default planner routing behavior for the iOS SDK.
///
/// Planner routing is ON by default when client auth/config credentials exist,
/// enabling server-side runtime plan resolution. When credentials are absent,
/// planner routing defaults to OFF and requests use direct/legacy routing
/// (offline app manifest/local assets).
///
/// Escape hatch: set ``OctomilConfig.plannerRouting`` to `false` to explicitly
/// disable planner routing regardless of credentials.
///
/// Privacy invariant: when routing policy is ``AppRoutingPolicy/private`` or
/// ``AppRoutingPolicy/localOnly``, requests NEVER route to cloud regardless
/// of planner state.
public enum PlannerRoutingDefaults {

    /// Resolve whether planner routing should be enabled.
    ///
    /// - Parameters:
    ///   - explicitOverride: Caller-provided override. `nil` means "use default".
    ///   - auth: The authentication configuration.
    /// - Returns: `true` if planner routing should be active.
    public static func resolve(
        explicitOverride: Bool?,
        auth: AuthConfig
    ) -> Bool {
        // Explicit override always wins
        if let override = explicitOverride {
            return override
        }

        // Default: ON when credentials exist that can reach a planner server
        return hasCredentials(auth: auth)
    }

    /// Whether the given auth config has credentials that can reach a planner.
    ///
    /// `orgApiKey`, `publishableKey`, and `deviceToken` all carry
    /// server-reachable credentials. `anonymous` does not.
    private static func hasCredentials(auth: AuthConfig) -> Bool {
        switch auth {
        case .orgApiKey(let apiKey, _, _):
            return !apiKey.isEmpty
        case .publishableKey(let key, _):
            return !key.isEmpty
        case .deviceToken(_, let token, _):
            return !token.isEmpty
        case .anonymous:
            return false
        }
    }

    /// Whether the given routing policy MUST block cloud routing.
    ///
    /// ``AppRoutingPolicy/private`` and ``AppRoutingPolicy/localOnly`` policies
    /// NEVER route to cloud, regardless of planner state, credentials, or
    /// server plan response.
    public static func isCloudBlocked(policy: AppRoutingPolicy?) -> Bool {
        guard let policy else { return false }
        switch policy {
        case .private, .localOnly:
            return true
        case .cloudOnly, .localFirst, .cloudFirst, .auto, .performanceFirst:
            return false
        }
    }

    /// Return the default routing policy based on planner state.
    ///
    /// When planner is enabled, defaults to `.auto` (server decides).
    /// When disabled, defaults to `.localFirst` (legacy behavior).
    public static func defaultPolicy(plannerEnabled: Bool) -> AppRoutingPolicy {
        return plannerEnabled ? .auto : .localFirst
    }
}

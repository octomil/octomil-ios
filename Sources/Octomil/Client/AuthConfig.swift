import Foundation

/// Authentication configuration for the Octomil SDK.
///
/// Use one of the provided cases to configure how the SDK authenticates:
///
/// ```swift
/// // Organization API key (for server-side, CLI, CI/CD)
/// let auth: AuthConfig = .orgApiKey(
///     apiKey: "edg_...",
///     orgId: "org_123"
/// )
///
/// // Device token (for edge devices with bootstrap flow)
/// let auth: AuthConfig = .deviceToken(
///     deviceId: "dev_abc",
///     bootstrapToken: "jwt..."
/// )
///
/// // Publishable key (for mobile/edge SDKs — safe to embed in client code)
/// let auth: AuthConfig = .publishableKey("oct_pub_...")
///
/// // Anonymous (local-only, no server registration)
/// let auth: AuthConfig = .anonymous(appId: "com.example.myapp")
///
/// let client = OctomilClient(auth: auth)
/// ```
public enum AuthConfig: Sendable {
    /// Organization-scoped API key authentication.
    ///
    /// - Parameters:
    ///   - apiKey: API key with `edg_` prefix.
    ///   - orgId: Organization identifier.
    ///   - serverURL: Base URL of the Octomil server.
    case orgApiKey(
        apiKey: String,
        orgId: String,
        serverURL: URL = OctomilClient.defaultServerURL
    )

    /// Short-lived device token authentication.
    ///
    /// Used by edge devices that go through a bootstrap/registration flow.
    ///
    /// - Parameters:
    ///   - deviceId: Stable device identifier (e.g., IDFV).
    ///   - bootstrapToken: Short-lived JWT from the bootstrap flow.
    ///   - serverURL: Base URL of the Octomil server.
    case deviceToken(
        deviceId: String,
        bootstrapToken: String,
        serverURL: URL = OctomilClient.defaultServerURL
    )

    /// Publishable key authentication for mobile/edge SDKs.
    ///
    /// Safe to embed in client code. Only `oct_pub_...` keys are accepted.
    /// Org info is extracted server-side from the key.
    ///
    /// - Parameters:
    ///   - key: Publishable key with `oct_pub_` prefix.
    ///   - serverURL: Base URL of the Octomil server.
    case publishableKey(
        _ key: String,
        serverURL: URL = OctomilClient.defaultServerURL
    )

    /// Anonymous / local-only mode. No server registration will occur.
    ///
    /// - Parameter appId: Application bundle identifier.
    case anonymous(appId: String)

    /// The bearer token used for API requests.
    var token: String {
        switch self {
        case .orgApiKey(let apiKey, _, _):
            return apiKey
        case .deviceToken(_, let bootstrapToken, _):
            return bootstrapToken
        case .publishableKey(let key, _):
            return key
        case .anonymous:
            return ""
        }
    }

    /// The organization ID, if applicable.
    var orgId: String {
        switch self {
        case .orgApiKey(_, let orgId, _):
            return orgId
        case .deviceToken:
            return ""
        case .publishableKey:
            // Org info is extracted server-side from the publishable key
            return ""
        case .anonymous:
            return ""
        }
    }

    /// The server URL.
    var serverURL: URL {
        switch self {
        case .orgApiKey(_, _, let serverURL):
            return serverURL
        case .deviceToken(_, _, let serverURL):
            return serverURL
        case .publishableKey(_, let serverURL):
            return serverURL
        case .anonymous:
            return OctomilClient.defaultServerURL
        }
    }

    /// The device ID, if using device token auth.
    var deviceId: String? {
        switch self {
        case .orgApiKey:
            return nil
        case .deviceToken(let deviceId, _, _):
            return deviceId
        case .publishableKey:
            return nil
        case .anonymous:
            return nil
        }
    }

    /// The ``AuthType`` enum value for this configuration.
    var authType: AuthType {
        switch self {
        case .orgApiKey:
            return .orgApiKey
        case .deviceToken:
            return .deviceToken
        case .publishableKey:
            return .serviceToken
        case .anonymous:
            return .deviceToken
        }
    }
}

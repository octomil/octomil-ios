import Foundation

/// Registration lifecycle state.
public enum RegistrationState: Sendable {
    case pending
    case registered
    case failed(Error)
}

/// Token lifecycle state.
public enum TokenState: Sendable {
    case none
    case valid(accessToken: String, expiresAt: Date)
    case expired
}

/// Thread-safe device identity and authentication context.
///
/// Created at ``OctomilClient/configure(manifest:auth:monitoring:)`` time
/// with a stable installation ID. Registration and token state are updated
/// in the background by ``OctomilClient/silentRegister()``.
public actor DeviceContext {
    /// Stable installation UUID persisted in Keychain (NOT IDFV).
    public let installationId: String

    /// Organization ID. Nil for local-only apps.
    public let orgId: String?

    /// App identifier (bundle ID).
    public let appId: String?

    private(set) var registrationState: RegistrationState = .pending
    private(set) var tokenState: TokenState = .none
    private(set) var serverDeviceId: String?

    public init(installationId: String, orgId: String? = nil, appId: String? = nil) {
        self.installationId = installationId
        self.orgId = orgId
        self.appId = appId
    }

    /// Whether the device has successfully registered with the server.
    public var isRegistered: Bool {
        if case .registered = registrationState { return true }
        return false
    }

    /// Returns Authorization headers if a valid (non-expired) access token exists.
    public func authHeaders() -> [String: String]? {
        switch tokenState {
        case .valid(let accessToken, let expiresAt):
            guard expiresAt > Date() else { return nil }
            return ["Authorization": "Bearer \(accessToken)"]
        default:
            return nil
        }
    }

    /// OTLP resource attributes derived from this context.
    public func telemetryResource() -> [String: String] {
        var resource: [String: String] = [
            "device.id": installationId,
            "platform": "ios",
        ]
        if let orgId { resource["org.id"] = orgId }
        if let appId { resource["app.id"] = appId }
        return resource
    }

    func updateRegistered(serverDeviceId: String, accessToken: String, expiresAt: Date) {
        self.serverDeviceId = serverDeviceId
        self.tokenState = .valid(accessToken: accessToken, expiresAt: expiresAt)
        self.registrationState = .registered
    }

    func updateToken(accessToken: String, expiresAt: Date) {
        self.tokenState = .valid(accessToken: accessToken, expiresAt: expiresAt)
    }

    func markFailed(_ error: Error) {
        self.registrationState = .failed(error)
    }

    func markTokenExpired() {
        self.tokenState = .expired
    }

    // MARK: - Installation ID

    private static let installationIdKey = "octomil_installation_id"

    /// Returns an existing installation ID from Keychain or creates a new random UUID.
    static func getOrCreateInstallationId(storage: SecureStorage) -> String {
        if let existing = try? storage.getClientDeviceIdentifier() {
            return existing
        }
        let newId = UUID().uuidString
        try? storage.storeClientDeviceIdentifier(newId)
        return newId
    }
}

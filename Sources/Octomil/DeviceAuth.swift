import Foundation
import Security

public struct DeviceTokenState: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresAt: Date
    public let orgId: String
    public let deviceIdentifier: String
    public let scopes: [String]

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case orgId = "org_id"
        case deviceIdentifier = "device_identifier"
        case scopes
    }
}

public protocol TokenStorage: Sendable {
    func save(_ data: Data, service: String, account: String) throws
    func load(service: String, account: String) throws -> Data
    func clear(service: String, account: String) throws
}

public struct KeychainTokenStorage: TokenStorage {
    public init() {
        // No configuration needed; all context is passed per-call via `service` and `account`.
    }

    public func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Octomil.DeviceAuth", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to store device token state in Keychain"
            ])
        }
    }

    public func load(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: "Octomil.DeviceAuth", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "No device token state found in Keychain"
            ])
        }
        return data
    }

    public func clear(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "Octomil.DeviceAuth", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to remove device token state from Keychain"
            ])
        }
    }
}

public actor DeviceAuthManager {
    private static let apiVersion = "v1"
    private static let authService = "device-auth"

    private static func authPath(_ action: String) -> String {
        "/api/\(apiVersion)/\(authService)/\(action)"
    }

    private let baseURL: URL
    private let orgId: String
    private let deviceIdentifier: String
    private let keychainService: String
    private let storage: TokenStorage
    private let session: URLSession

    // swiftlint:disable:next line_length
    public init(baseURL: URL, orgId: String, deviceIdentifier: String, keychainService: String = "ai.octomil", storage: TokenStorage = KeychainTokenStorage(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.orgId = orgId
        self.deviceIdentifier = deviceIdentifier
        self.keychainService = keychainService
        self.storage = storage
        self.session = session
    }

    private var storageAccount: String {
        "\(orgId):\(deviceIdentifier)"
    }

    public func bootstrap(
        bootstrapBearerToken: String,
        scopes: [String] = ["devices:write"],
        accessTTLSeconds: Int? = nil,
        deviceId: String? = nil
    ) async throws -> DeviceTokenState {
        var payload: [String: Any] = [
            "org_id": orgId,
            "device_identifier": deviceIdentifier,
            "scopes": scopes,
        ]
        if let accessTTLSeconds {
            payload["access_ttl_seconds"] = accessTTLSeconds
        }
        if let deviceId {
            payload["device_id"] = deviceId
        }

        let data = try await postJSON(
            path: Self.authPath("bootstrap"),
            jsonBody: payload,
            bearerToken: bootstrapBearerToken,
            expectedStatusCodes: [200, 201]
        )
        let state = try decodeTokenState(from: data)
        try save(state)
        return state
    }

    public func refresh() async throws -> DeviceTokenState {
        let current = try load()
        let data = try await postJSON(
            path: Self.authPath("refresh"),
            jsonBody: ["refresh_token": current.refreshToken],
            bearerToken: nil,
            expectedStatusCodes: [200]
        )
        let next = try decodeTokenState(from: data)
        try save(next)
        return next
    }

    public func revoke(reason: String = "sdk_revoke") async throws {
        guard let current = try? load() else {
            return
        }

        _ = try await postJSON(
            path: Self.authPath("revoke"),
            jsonBody: ["refresh_token": current.refreshToken, "reason": reason],
            bearerToken: nil,
            expectedStatusCodes: [200, 204]
        )
        try clear()
    }

    public func getAccessToken(refreshIfExpiringWithin seconds: TimeInterval = 30) async throws -> String {
        let current = try load()
        if Date().addingTimeInterval(seconds) >= current.expiresAt {
            do {
                return try await refresh().accessToken
            } catch {
                // Offline-safe fallback: continue with current token until hard expiry.
                if Date() < current.expiresAt {
                    return current.accessToken
                }
                throw error
            }
        }
        return current.accessToken
    }

    private func postJSON(
        path: String,
        jsonBody: [String: Any],
        bearerToken: String?,
        expectedStatusCodes: Set<Int>
    ) async throws -> Data {
        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !expectedStatusCodes.contains(status) {
            throw NSError(
                domain: "Octomil.DeviceAuth",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Device auth request failed with status \(status)"]
            )
        }
        return data
    }

    private func decodeTokenState(from data: Data) throws -> DeviceTokenState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: value)
                ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date: \(value)")
        }
        return try decoder.decode(DeviceTokenState.self, from: data)
    }

    private func save(_ state: DeviceTokenState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.withFractional.string(from: date))
        }
        let encoded = try encoder.encode(state)
        try storage.save(encoded, service: keychainService, account: storageAccount)
    }

    private func load() throws -> DeviceTokenState {
        let data = try storage.load(service: keychainService, account: storageAccount)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: value)
                ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date: \(value)")
        }
        return try decoder.decode(DeviceTokenState.self, from: data)
    }

    private func clear() throws {
        try storage.clear(service: keychainService, account: storageAccount)
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

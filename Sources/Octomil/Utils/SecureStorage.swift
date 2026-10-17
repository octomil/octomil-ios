import Foundation
import Security
import os.log

/// Secure storage for API keys and credentials using Keychain.
public final class SecureStorage: @unchecked Sendable {

    // MARK: - Constants

    private static let service = "ai.octomil.sdk"
    private static let apiKeyAccount = "api_key"
    private static let deviceTokenAccount = "device_token"
    private static let deviceIdAccount = "device_id"
    private static let serverDeviceIdAccount = "server_device_id"
    private static let clientDeviceIdentifierAccount = "client_device_identifier"

    // MARK: - Properties

    private let logger: Logger

    // MARK: - Initialization

    /// Creates a new secure storage instance.
    public init() {
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "SecureStorage")
    }

    // MARK: - API Key

    /// Stores the API key securely.
    /// - Parameter key: API key to store.
    /// - Throws: `OctomilError.keychainError` if storage fails.
    public func storeAPIKey(_ key: String) throws {
        try store(value: key, account: Self.apiKeyAccount)
    }

    /// Retrieves the stored API key.
    /// - Returns: The API key, or nil if not stored.
    /// - Throws: `OctomilError.keychainError` if retrieval fails.
    public func getAPIKey() throws -> String? {
        return try retrieve(account: Self.apiKeyAccount)
    }

    /// Deletes the stored API key.
    /// - Throws: `OctomilError.keychainError` if deletion fails.
    public func deleteAPIKey() throws {
        try delete(account: Self.apiKeyAccount)
    }

    // MARK: - Device Token

    /// Stores the device token securely.
    /// - Parameter token: Device token to store.
    /// - Throws: `OctomilError.keychainError` if storage fails.
    public func storeDeviceToken(_ token: String) throws {
        try store(value: token, account: Self.deviceTokenAccount)
    }

    /// Retrieves the stored device token.
    /// - Returns: The device token, or nil if not stored.
    /// - Throws: `OctomilError.keychainError` if retrieval fails.
    public func getDeviceToken() throws -> String? {
        return try retrieve(account: Self.deviceTokenAccount)
    }

    /// Deletes the stored device token.
    /// - Throws: `OctomilError.keychainError` if deletion fails.
    public func deleteDeviceToken() throws {
        try delete(account: Self.deviceTokenAccount)
    }

    // MARK: - Device ID

    /// Stores the device ID securely.
    /// - Parameter deviceId: Device ID to store.
    /// - Throws: `OctomilError.keychainError` if storage fails.
    public func storeDeviceId(_ deviceId: String) throws {
        try store(value: deviceId, account: Self.deviceIdAccount)
    }

    /// Retrieves the stored device ID.
    /// - Returns: The device ID, or nil if not stored.
    /// - Throws: `OctomilError.keychainError` if retrieval fails.
    public func getDeviceId() throws -> String? {
        return try retrieve(account: Self.deviceIdAccount)
    }

    // MARK: - Server Device ID

    /// Stores the server-assigned device UUID securely.
    /// - Parameter deviceId: Server device UUID to store.
    /// - Throws: `OctomilError.keychainError` if storage fails.
    public func storeServerDeviceId(_ deviceId: String) throws {
        try store(value: deviceId, account: Self.serverDeviceIdAccount)
    }

    /// Retrieves the stored server device UUID.
    /// - Returns: The server device UUID, or nil if not stored.
    /// - Throws: `OctomilError.keychainError` if retrieval fails.
    public func getServerDeviceId() throws -> String? {
        return try retrieve(account: Self.serverDeviceIdAccount)
    }

    // MARK: - Client Device Identifier

    /// Stores the client-generated device identifier securely.
    /// - Parameter identifier: Client device identifier to store.
    /// - Throws: `OctomilError.keychainError` if storage fails.
    public func storeClientDeviceIdentifier(_ identifier: String) throws {
        try store(value: identifier, account: Self.clientDeviceIdentifierAccount)
    }

    /// Retrieves the stored client device identifier.
    /// - Returns: The client device identifier, or nil if not stored.
    /// - Throws: `OctomilError.keychainError` if retrieval fails.
    public func getClientDeviceIdentifier() throws -> String? {
        return try retrieve(account: Self.clientDeviceIdentifierAccount)
    }

    // MARK: - Clear All

    /// Clears all stored credentials.
    public func clearAll() {
        try? deleteAPIKey()
        try? deleteDeviceToken()
        try? delete(account: Self.deviceIdAccount)
        try? delete(account: Self.serverDeviceIdAccount)
        try? delete(account: Self.clientDeviceIdentifierAccount)
    }

    // MARK: - Private Methods

    private func store(value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw OctomilError.keychainError(status: errSecParam)
        }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        var status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(identity.merging(attributes) { $1 } as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            logger.error("Keychain store failed: \(status)")
            throw OctomilError.keychainError(status: status)
        }
    }

    private func retrieve(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("Keychain retrieve failed: \(status)")
            throw OctomilError.keychainError(status: status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status)")
            throw OctomilError.keychainError(status: status)
        }
    }
}

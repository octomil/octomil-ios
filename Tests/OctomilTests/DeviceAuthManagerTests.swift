import Foundation
import XCTest
@testable import Octomil

final class DeviceAuthManagerTests: XCTestCase {
    fileprivate static let testHost = "api.example.com"
    private static let testBaseURL = URL(string: "https://\(testHost)")!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = Self.testHost
    }

    func testBootstrapRefreshRevokeLifecycle() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(900))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .success(
                statusCode: 200,
                json: tokenPayload(access: "acc_refresh", refresh: "ref_refresh", expiresAt: exp)
            ),
            .success(statusCode: 204, json: [:]),
        ]

        let bootstrapped = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        XCTAssertEqual(bootstrapped.accessToken, "acc_bootstrap")

        let refreshed = try await manager.refresh()
        XCTAssertEqual(refreshed.accessToken, "acc_refresh")
        XCTAssertEqual(refreshed.refreshToken, "ref_refresh")

        try await manager.revoke()

        do {
            _ = try await manager.getAccessToken()
            XCTFail("Expected no token state after revoke")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "Octomil.DeviceAuth",
                           "Expected Octomil.DeviceAuth error after revoke, got: \(error)")
        }
    }

    func testBootstrapSendsExpectedPayloadAndBearerToken() async throws {
        let fixture = makeManager()
        let manager = fixture.manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(900))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
        ]

        _ = try await manager.bootstrap(
            bootstrapBearerToken: "bootstrap-token",
            scopes: ["devices:write", "heartbeat:write"],
            accessTTLSeconds: 600,
            deviceId: "device-db-id"
        )

        XCTAssertEqual(SharedMockURLProtocol.requests.count, 1)
        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/device-auth/bootstrap")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bootstrap-token")
        let payload = try jsonBody(request)
        XCTAssertEqual(payload["org_id"] as? String, fixture.orgId)
        XCTAssertEqual(payload["device_identifier"] as? String, fixture.deviceIdentifier)
        XCTAssertEqual(payload["access_ttl_seconds"] as? Int, 600)
        XCTAssertEqual(payload["device_id"] as? String, "device-db-id")
        XCTAssertEqual(payload["scopes"] as? [String], ["devices:write", "heartbeat:write"])
    }

    func testRefreshUsesLatestRefreshTokenAfterRotation() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(900))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .success(
                statusCode: 200,
                json: tokenPayload(access: "acc_refresh_1", refresh: "ref_refresh_1", expiresAt: exp)
            ),
            .success(
                statusCode: 200,
                json: tokenPayload(access: "acc_refresh_2", refresh: "ref_refresh_2", expiresAt: exp)
            ),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        _ = try await manager.refresh()
        _ = try await manager.refresh()

        XCTAssertEqual(SharedMockURLProtocol.requests.count, 3)
        let firstRefreshPayload = try jsonBody(try XCTUnwrap(SharedMockURLProtocol.requests[safe: 1]))
        let secondRefreshPayload = try jsonBody(try XCTUnwrap(SharedMockURLProtocol.requests[safe: 2]))
        XCTAssertEqual(firstRefreshPayload["refresh_token"] as? String, "ref_bootstrap")
        XCTAssertEqual(secondRefreshPayload["refresh_token"] as? String, "ref_refresh_1")
    }

    func testGetAccessTokenFallsBackWhenRefreshFailsAndTokenStillValid() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(300))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .failure(URLError(.notConnectedToInternet)),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        let token = try await manager.getAccessToken(refreshIfExpiringWithin: 600)
        XCTAssertEqual(token, "acc_bootstrap")
    }

    func testGetAccessTokenThrowsWhenExpiredAndRefreshFails() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let expired = formatter.string(from: Date().addingTimeInterval(-60))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_expired", refresh: "ref_expired", expiresAt: expired)
            ),
            .failure(URLError(.cannotConnectToHost)),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")

        do {
            _ = try await manager.getAccessToken(refreshIfExpiringWithin: 30)
            XCTFail("Expected refresh failure to surface for expired token")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotConnectToHost,
                           "Expected cannotConnectToHost error, got: \(error)")
        } catch {
            XCTFail("Expected URLError, got \(type(of: error)): \(error)")
        }
    }

    func testGetAccessTokenReturnsCurrentTokenWhenNotNearExpiry() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(3600))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        let token = try await manager.getAccessToken(refreshIfExpiringWithin: 30)
        XCTAssertEqual(token, "acc_bootstrap")
        XCTAssertEqual(SharedMockURLProtocol.requests.count, 1)
    }

    func testRevokeFailurePreservesStoredState() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(600))

        SharedMockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .failure(URLError(.cannotConnectToHost)),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")

        do {
            try await manager.revoke()
            XCTFail("Expected revoke failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotConnectToHost,
                           "Expected cannotConnectToHost error, got: \(error)")
        } catch {
            XCTFail("Expected URLError, got \(type(of: error)): \(error)")
        }

        let token = try await manager.getAccessToken(refreshIfExpiringWithin: 30)
        XCTAssertEqual(token, "acc_bootstrap")
    }

    private func makeManager() -> (manager: DeviceAuthManager, orgId: String, deviceIdentifier: String) {
        let unique = UUID().uuidString
        let orgId = "org-\(unique)"
        let deviceIdentifier = "device-\(unique)"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]
        return (
            DeviceAuthManager(
                baseURL: Self.testBaseURL,
                orgId: orgId,
                deviceIdentifier: deviceIdentifier,
                keychainService: "ai.octomil.tests.\(unique)",
                storage: InMemoryTokenStorage(),
                session: URLSession(configuration: config)
            ),
            orgId,
            deviceIdentifier
        )
    }

    private func tokenPayload(access: String, refresh: String, expiresAt: String) -> [String: Any] {
        [
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "Bearer",
            "expires_at": expiresAt,
            "org_id": "org-1",
            "device_identifier": "device-1",
            "scopes": ["devices:write"],
        ]
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

}

private final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }

    func save(_ data: Data, service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store[key(service: service, account: account)] = data
    }

    func load(service: String, account: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let data = store[key(service: service, account: account)] else {
            throw NSError(domain: "Octomil.DeviceAuth", code: -25300, userInfo: [
                NSLocalizedDescriptionKey: "No device token state found"
            ])
        }
        return data
    }

    func clear(service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key(service: service, account: account))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

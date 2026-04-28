import Foundation
import XCTest
@testable import Octomil

/// Tests for ``APIClient`` header configuration, error mapping, response decoding,
/// and retry logic using ``SharedMockURLProtocol``.
final class APIClientTests: XCTestCase {

    private static let testHost = "api.test.octomil.com"
    private static let testBaseURL = URL(string: "https://\(testHost)")!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = Self.testHost
    }

    // MARK: - Helpers

    private func makeClient(
        maxRetryAttempts: Int = 1,
        requestTimeout: Double = 5
    ) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]

        return APIClient(
            serverURL: Self.testBaseURL,
            configuration: TestConfiguration.fast(
                maxRetryAttempts: maxRetryAttempts,
                requestTimeout: requestTimeout
            ),
            sessionConfiguration: config
        )
    }

    // MARK: - Token management

    func testSetAndGetDeviceToken() async {
        let client = makeClient()
        let initial = await client.getDeviceToken()
        XCTAssertNil(initial)

        await client.setDeviceToken("test-token")
        let token = await client.getDeviceToken()
        XCTAssertEqual(token, "test-token")
    }

    // MARK: - Header configuration

    func testRequestIncludesAuthorizationHeader() async throws {
        let client = makeClient()
        await client.setDeviceToken("my-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: heartbeatJSON()),
        ]

        _ = try await client.sendHeartbeat(deviceId: "device-1")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
    }

    func testRequestIncludesUserAgent() async throws {
        let client = makeClient()
        await client.setDeviceToken("my-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: heartbeatJSON()),
        ]

        _ = try await client.sendHeartbeat(deviceId: "device-1")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "octomil-ios/1.0")
    }

    func testMissingTokenThrowsAuthenticationFailed() async {
        let client = makeClient()
        // Don't set token

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected authentication error")
        } catch let error as OctomilError {
            if case .authenticationFailed(let reason) = error {
                XCTAssertTrue(reason.contains("Missing"))
            } else {
                XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - HTTP error mapping

    func testHTTP401MapsToInvalidAPIKey() async {
        let client = makeClient()
        await client.setDeviceToken("expired-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 401, json: ["detail": "Token expired"]),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            // APIClient.swift maps 401 → authenticationFailed(reason)
            // when the response body lacks a contract ``code`` field.
            if case .authenticationFailed(let reason) = error {
                XCTAssertEqual(reason, "Token expired")
            } else {
                XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTP403MapsToAuthenticationFailed() async {
        let client = makeClient()
        await client.setDeviceToken("some-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 403, json: ["detail": "Forbidden access"]),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            // APIClient.swift maps 403 → forbidden(reason).
            if case .forbidden(let reason) = error {
                XCTAssertEqual(reason, "Forbidden access")
            } else {
                XCTFail("Expected forbidden, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTP500MapsToServerError() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["detail": "Internal error"]),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .serverError(let statusCode, let message) = error {
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(message, "Internal error")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTP404MapsToServerError() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 404, json: ["detail": "Not found"]),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .serverError(let statusCode, let message) = error {
                XCTAssertEqual(statusCode, 404)
                XCTAssertEqual(message, "Not found")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - URL error mapping

    func testURLErrorNotConnectedMapsToNetworkUnavailable() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .failure(URLError(.notConnectedToInternet)),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .networkUnavailable = error {
                // Expected
            } else {
                XCTFail("Expected networkUnavailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testURLErrorTimedOutMapsToRequestTimeout() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .failure(URLError(.timedOut)),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .requestTimeout = error {
                // Expected
            } else {
                XCTFail("Expected requestTimeout, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testURLErrorCancelledMapsToCancelled() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .failure(URLError(.cancelled)),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .cancelled = error {
                // Expected
            } else {
                XCTFail("Expected cancelled, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testURLErrorConnectionLostMapsToNetworkUnavailable() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .failure(URLError(.networkConnectionLost)),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .networkUnavailable = error {
                // Expected
            } else {
                XCTFail("Expected networkUnavailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Response decoding

    func testValidJSONDecoding() async throws {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: heartbeatJSON()),
        ]

        let response = try await client.sendHeartbeat(deviceId: "device-1")
        XCTAssertEqual(response.id, "device-uuid")
        XCTAssertEqual(response.deviceIdentifier, "device-1")
        XCTAssertEqual(response.status, "active")
    }

    func testInvalidJSONThrowsDecodingError() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["unexpected": "format"]),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected decoding error")
        } catch let error as OctomilError {
            if case .decodingError = error {
                // Expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Error message parsing

    func testErrorMessageParsedFromJSON() async {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["detail": "Database connection failed"]),
        ]

        do {
            _ = try await client.sendHeartbeat(deviceId: "device-1")
            XCTFail("Expected error")
        } catch let error as OctomilError {
            if case .serverError(_, let message) = error {
                XCTAssertEqual(message, "Database connection failed")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - URL path construction

    func testHeartbeatURLPath() async throws {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: heartbeatJSON()),
        ]

        _ = try await client.sendHeartbeat(deviceId: "my-device-id")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertTrue(request.url?.path.contains("api/v1/devices/my-device-id/heartbeat") == true)
    }

    func testDeviceGroupsURLPath() async throws {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["groups": []]),
        ]

        _ = try await client.getDeviceGroups(deviceId: "d-123")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertTrue(request.url?.path.contains("api/v1/devices/d-123/groups") == true)
    }

    // MARK: - checkForUpdates

    func testCheckForUpdatesReturnsNilOn404() async throws {
        let client = makeClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 404, json: ["detail": "No update"]),
        ]

        let result = try await client.checkForUpdates(modelId: "model-1", currentVersion: "1.0.0")
        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func heartbeatJSON() -> [String: Any] {
        [
            "id": "device-uuid",
            "device_identifier": "device-1",
            "status": "active",
            "last_heartbeat": "2026-02-09T12:00:00Z",
        ]
    }
}

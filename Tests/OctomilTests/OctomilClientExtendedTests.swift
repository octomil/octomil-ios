import CoreML
import Foundation
import XCTest
@testable import Octomil

/// Extended tests for ``OctomilClient`` covering guard clauses in extension
/// methods that require device registration.
///
/// Every method that checks ``self.deviceId`` should throw
/// ``OctomilError.deviceNotRegistered`` when called before ``register()``.
final class OctomilClientExtendedTests: XCTestCase {

    private static let testHost = "api.test.octomil.com"
    private static let testServerURL = URL(string: "https://\(testHost)")!

    private func makeClient() -> OctomilClient {
        return OctomilClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL,
            configuration: TestConfiguration.fast()
        )
    }

    // MARK: - sendHeartbeat guard

    func testSendHeartbeatThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.sendHeartbeat()
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSendHeartbeatWithStorageThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.sendHeartbeat(availableStorageMb: 1024)
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - getGroups guard

    func testGetGroupsThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.getGroups()
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - isMemberOf(groupId:) guard

    func testIsMemberOfGroupIdThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.isMemberOf(groupId: "group-123")
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - isMemberOf(groupName:) guard

    func testIsMemberOfGroupNameThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.isMemberOf(groupName: "beta-testers")
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - getDeviceInfo guard

    func testGetDeviceInfoThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.getDeviceInfo()
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - downloadModel guard

    func testDownloadModelThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.downloadModel(modelId: "test-model")
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDownloadModelWithVersionThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.downloadModel(modelId: "test-model", version: "1.0.0")
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - joinRound guard

    func testJoinRoundThrowsDeviceNotRegistered() async {
        let client = makeClient()

        do {
            _ = try await client.joinRound(
                modelId: "test-model",
                dataProvider: { MockBatchProviderExtended() }
            )
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as OctomilError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Expected deviceNotRegistered, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - checkForUpdates (no guard, but returns nil without cached model)

    func testCheckForUpdatesReturnsNilWithoutCachedModel() async throws {
        let client = makeClient()
        let result = try await client.checkForUpdates(modelId: "nonexistent")
        XCTAssertNil(result)
    }

    // MARK: - getCachedModel

    func testGetCachedModelReturnsNilWithoutDownload() {
        let client = makeClient()
        XCTAssertNil(client.getCachedModel(modelId: "any-model"))
    }

    func testGetCachedModelWithVersionReturnsNilWithoutDownload() {
        let client = makeClient()
        XCTAssertNil(client.getCachedModel(modelId: "any-model", version: "1.0.0"))
    }

    // MARK: - isRegistered / deviceId / deviceIdentifier before registration

    func testIsRegisteredFalseInitially() {
        let client = makeClient()
        XCTAssertFalse(client.isRegistered)
    }

    func testDeviceIdNilBeforeRegistration() {
        let client = makeClient()
        XCTAssertNil(client.deviceId)
    }

    func testDeviceIdentifierNilBeforeRegistration() {
        let client = makeClient()
        XCTAssertNil(client.deviceIdentifier)
    }

    // MARK: - orgId

    func testOrgIdPreserved() {
        let client = OctomilClient(
            deviceAccessToken: "tok",
            orgId: "my-org-456",
            serverURL: Self.testServerURL
        )
        XCTAssertEqual(client.orgId, "my-org-456")
    }

    // MARK: - stopHeartbeat

    func testStopHeartbeatDoesNotCrash() {
        let client = makeClient()
        client.stopHeartbeat()
        // Should not crash even without starting heartbeat
    }

    func testStartThenStopHeartbeatDoesNotCrash() {
        let client = makeClient()
        client.startHeartbeat()
        client.stopHeartbeat()
    }

    // MARK: - Background training

    #if os(iOS)
    func testEnableAndDisableBackgroundTraining() {
        let client = makeClient()

        client.enableBackgroundTraining(
            modelId: "test-model",
            dataProvider: { MockBatchProviderExtended() },
            constraints: .standard
        )

        client.disableBackgroundTraining()
    }

    func testBackgroundTrainingRelaxedConstraints() {
        let client = makeClient()

        client.enableBackgroundTraining(
            modelId: "test-model",
            dataProvider: { MockBatchProviderExtended() },
            constraints: .relaxed
        )

        client.disableBackgroundTraining()
    }
    #endif

    // MARK: - Static properties

    func testDefaultServerHost() {
        XCTAssertEqual(OctomilClient.defaultServerHost, "api.octomil.com")
    }

    func testDefaultServerURL() {
        XCTAssertEqual(OctomilClient.defaultServerURL.scheme, "https")
        XCTAssertEqual(OctomilClient.defaultServerURL.host, "api.octomil.com")
    }
}

// MARK: - Mock

private class MockBatchProviderExtended: MLBatchProvider {
    var count: Int { return 0 }

    func features(at _: Int) -> MLFeatureProvider {
        fatalError("Not implemented for tests")
    }
}

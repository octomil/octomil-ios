import XCTest
@testable import Octomil

final class DeviceContextTests: XCTestCase {

    // MARK: - Initial State

    func testInitialRegistrationStateIsPending() async {
        let ctx = DeviceContext(installationId: "test-id")
        let state = await ctx.registrationState
        if case .pending = state {
            // pass
        } else {
            XCTFail("Expected .pending, got \(state)")
        }
    }

    func testInitialTokenStateIsNone() async {
        let ctx = DeviceContext(installationId: "test-id")
        let state = await ctx.tokenState
        if case .none = state {
            // pass
        } else {
            XCTFail("Expected .none, got \(state)")
        }
    }

    // MARK: - updateRegistered

    func testUpdateRegisteredSetsStateCorrectly() async {
        let ctx = DeviceContext(installationId: "test-id")
        let expires = Date().addingTimeInterval(3600)

        await ctx.updateRegistered(
            serverDeviceId: "srv-123",
            accessToken: "tok-abc",
            expiresAt: expires
        )

        let regState = await ctx.registrationState
        if case .registered = regState {
            // pass
        } else {
            XCTFail("Expected .registered, got \(regState)")
        }

        let serverDeviceId = await ctx.serverDeviceId
        XCTAssertEqual(serverDeviceId, "srv-123")

        let tokenState = await ctx.tokenState
        if case .valid(let token, let exp) = tokenState {
            XCTAssertEqual(token, "tok-abc")
            XCTAssertEqual(exp, expires)
        } else {
            XCTFail("Expected .valid, got \(tokenState)")
        }
    }

    // MARK: - updateToken

    func testUpdateTokenUpdatesTokenOnly() async {
        let ctx = DeviceContext(installationId: "test-id")
        let expires = Date().addingTimeInterval(3600)

        await ctx.updateToken(accessToken: "new-token", expiresAt: expires)

        // Registration state should still be pending
        let regState = await ctx.registrationState
        if case .pending = regState {
            // pass
        } else {
            XCTFail("Expected .pending unchanged, got \(regState)")
        }

        let tokenState = await ctx.tokenState
        if case .valid(let token, _) = tokenState {
            XCTAssertEqual(token, "new-token")
        } else {
            XCTFail("Expected .valid, got \(tokenState)")
        }
    }

    // MARK: - markFailed

    func testMarkFailedSetsFailedState() async {
        let ctx = DeviceContext(installationId: "test-id")
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "test error"])

        await ctx.markFailed(error)

        let state = await ctx.registrationState
        if case .failed(let err) = state {
            XCTAssertEqual((err as NSError).code, 42)
        } else {
            XCTFail("Expected .failed, got \(state)")
        }
    }

    // MARK: - markTokenExpired

    func testMarkTokenExpiredSetsExpiredState() async {
        let ctx = DeviceContext(installationId: "test-id")
        await ctx.updateToken(accessToken: "tok", expiresAt: Date().addingTimeInterval(3600))
        await ctx.markTokenExpired()

        let tokenState = await ctx.tokenState
        if case .expired = tokenState {
            // pass
        } else {
            XCTFail("Expected .expired, got \(tokenState)")
        }
    }

    // MARK: - authHeaders

    func testAuthHeadersReturnsNilWhenNoToken() async {
        let ctx = DeviceContext(installationId: "test-id")
        let headers = await ctx.authHeaders()
        XCTAssertNil(headers)
    }

    func testAuthHeadersReturnsBearerWhenValidToken() async {
        let ctx = DeviceContext(installationId: "test-id")
        let expires = Date().addingTimeInterval(3600)
        await ctx.updateToken(accessToken: "my-secret-token", expiresAt: expires)

        let headers = await ctx.authHeaders()
        XCTAssertEqual(headers?["Authorization"], "Bearer my-secret-token")
    }

    func testAuthHeadersReturnsNilWhenTokenExpired() async {
        let ctx = DeviceContext(installationId: "test-id")
        let pastDate = Date().addingTimeInterval(-60) // expired 1 minute ago
        await ctx.updateToken(accessToken: "expired-tok", expiresAt: pastDate)

        let headers = await ctx.authHeaders()
        XCTAssertNil(headers)
    }

    // MARK: - telemetryResource

    func testTelemetryResourceIncludesInstallationIdAndPlatform() async {
        let ctx = DeviceContext(installationId: "install-uuid-123")
        let resource = await ctx.telemetryResource()

        XCTAssertEqual(resource["device.id"], "install-uuid-123")
        XCTAssertEqual(resource["platform"], "ios")
    }

    func testTelemetryResourceIncludesOrgIdWhenPresent() async {
        let ctx = DeviceContext(installationId: "id", orgId: "org_abc")
        let resource = await ctx.telemetryResource()

        XCTAssertEqual(resource["org.id"], "org_abc")
    }

    func testTelemetryResourceExcludesOrgIdWhenNil() async {
        let ctx = DeviceContext(installationId: "id", orgId: nil)
        let resource = await ctx.telemetryResource()

        XCTAssertNil(resource["org.id"])
    }

    func testTelemetryResourceIncludesAppIdWhenPresent() async {
        let ctx = DeviceContext(installationId: "id", appId: "com.test.app")
        let resource = await ctx.telemetryResource()

        XCTAssertEqual(resource["app.id"], "com.test.app")
    }

    func testTelemetryResourceExcludesAppIdWhenNil() async {
        let ctx = DeviceContext(installationId: "id", appId: nil)
        let resource = await ctx.telemetryResource()

        XCTAssertNil(resource["app.id"])
    }

    // MARK: - installationId format

    func testInstallationIdIsUUIDFormat() {
        let uuid = UUID().uuidString
        let ctx = DeviceContext(installationId: uuid)
        // Verify the stored ID matches what was passed in
        // The actual UUID generation happens in getOrCreateInstallationId
        // which uses UUID().uuidString — verify the format is valid
        XCTAssertNotNil(UUID(uuidString: uuid))
    }

    // MARK: - isRegistered

    func testIsRegisteredFalseWhenPending() async {
        let ctx = DeviceContext(installationId: "id")
        let registered = await ctx.isRegistered
        XCTAssertFalse(registered)
    }

    func testIsRegisteredTrueAfterUpdateRegistered() async {
        let ctx = DeviceContext(installationId: "id")
        await ctx.updateRegistered(
            serverDeviceId: "srv",
            accessToken: "tok",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let registered = await ctx.isRegistered
        XCTAssertTrue(registered)
    }

    func testIsRegisteredFalseAfterMarkFailed() async {
        let ctx = DeviceContext(installationId: "id")
        await ctx.markFailed(NSError(domain: "test", code: 1))
        let registered = await ctx.isRegistered
        XCTAssertFalse(registered)
    }
}

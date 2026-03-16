import XCTest
@testable import Octomil

final class AuthConfigTests: XCTestCase {

    // MARK: - publishableKey (basic)

    func testPublishableKeyToken() {
        let auth = AuthConfig.publishableKey("oct_pub_test_123")
        XCTAssertEqual(auth.token, "oct_pub_test_123")
    }

    func testPublishableKeyOrgIdIsEmpty() {
        let auth = AuthConfig.publishableKey("oct_pub_test_123")
        XCTAssertEqual(auth.orgId, "")
    }

    func testPublishableKeyServerURL() {
        let auth = AuthConfig.publishableKey("oct_pub_test_123")
        XCTAssertEqual(auth.serverURL, OctomilClient.defaultServerURL)
    }

    func testPublishableKeyCustomServerURL() {
        let custom = URL(string: "https://custom.example.com")!
        let auth = AuthConfig.publishableKey("oct_pub_test_123", serverURL: custom)
        XCTAssertEqual(auth.serverURL, custom)
    }

    func testPublishableKeyDeviceIdIsNil() {
        let auth = AuthConfig.publishableKey("oct_pub_test_123")
        XCTAssertNil(auth.deviceId)
    }

    // MARK: - validatedPublishableKey

    func testValidatedPublishableKeyAcceptsTestPrefix() {
        let auth = AuthConfig.validatedPublishableKey("oct_pub_test_abc")
        XCTAssertEqual(auth.token, "oct_pub_test_abc")
    }

    func testValidatedPublishableKeyAcceptsLivePrefix() {
        let auth = AuthConfig.validatedPublishableKey("oct_pub_live_abc")
        XCTAssertEqual(auth.token, "oct_pub_live_abc")
    }

    func testValidatedPublishableKeyCustomServerURL() {
        let custom = URL(string: "https://custom.example.com")!
        let auth = AuthConfig.validatedPublishableKey("oct_pub_test_abc", serverURL: custom)
        XCTAssertEqual(auth.serverURL, custom)
    }

    // MARK: - publishableKeyEnvironment

    func testPublishableKeyEnvironmentTest() {
        let auth = AuthConfig.publishableKey("oct_pub_test_abc")
        XCTAssertEqual(auth.publishableKeyEnvironment, "test")
    }

    func testPublishableKeyEnvironmentLive() {
        let auth = AuthConfig.publishableKey("oct_pub_live_abc")
        XCTAssertEqual(auth.publishableKeyEnvironment, "live")
    }

    func testPublishableKeyEnvironmentNilForBarePrefix() {
        let auth = AuthConfig.publishableKey("oct_pub_abc")
        XCTAssertNil(auth.publishableKeyEnvironment)
    }

    func testPublishableKeyEnvironmentNilForOtherAuthTypes() {
        let auth = AuthConfig.anonymous(appId: "com.example.app")
        XCTAssertNil(auth.publishableKeyEnvironment)
    }

    // MARK: - deviceToken (bootstrapToken)

    func testDeviceTokenAuth() {
        let auth = AuthConfig.deviceToken(deviceId: "dev_abc", bootstrapToken: "jwt-xyz")
        XCTAssertEqual(auth.token, "jwt-xyz")
        XCTAssertEqual(auth.deviceId, "dev_abc")
    }

    func testDeviceTokenOrgIdIsEmpty() {
        let auth = AuthConfig.deviceToken(deviceId: "dev_abc", bootstrapToken: "jwt-xyz")
        XCTAssertEqual(auth.orgId, "")
    }

    func testDeviceTokenServerURL() {
        let auth = AuthConfig.deviceToken(deviceId: "dev_abc", bootstrapToken: "jwt-xyz")
        XCTAssertEqual(auth.serverURL, OctomilClient.defaultServerURL)
    }

    // MARK: - anonymous

    func testAnonymousToken() {
        let auth = AuthConfig.anonymous(appId: "com.example.myapp")
        XCTAssertEqual(auth.token, "")
    }

    func testAnonymousOrgIdIsEmpty() {
        let auth = AuthConfig.anonymous(appId: "com.example.myapp")
        XCTAssertEqual(auth.orgId, "")
    }

    func testAnonymousServerURL() {
        let auth = AuthConfig.anonymous(appId: "com.example.myapp")
        XCTAssertEqual(auth.serverURL, OctomilClient.defaultServerURL)
    }

    func testAnonymousDeviceIdIsNil() {
        let auth = AuthConfig.anonymous(appId: "com.example.myapp")
        XCTAssertNil(auth.deviceId)
    }

    // MARK: - orgApiKey

    func testOrgApiKeyToken() {
        let auth = AuthConfig.orgApiKey(apiKey: "edg_key123", orgId: "org_456")
        XCTAssertEqual(auth.token, "edg_key123")
    }

    func testOrgApiKeyOrgId() {
        let auth = AuthConfig.orgApiKey(apiKey: "edg_key123", orgId: "org_456")
        XCTAssertEqual(auth.orgId, "org_456")
    }

    func testOrgApiKeyServerURL() {
        let auth = AuthConfig.orgApiKey(apiKey: "edg_key123", orgId: "org_456")
        XCTAssertEqual(auth.serverURL, OctomilClient.defaultServerURL)
    }

    func testOrgApiKeyDeviceIdIsNil() {
        let auth = AuthConfig.orgApiKey(apiKey: "edg_key123", orgId: "org_456")
        XCTAssertNil(auth.deviceId)
    }
}

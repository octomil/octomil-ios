import Foundation
import XCTest
@testable import Octomil

/// Verifies that the routing request body shape matches the server contract:
/// - `deployment_id` present when configured
/// - `prefer` omitted when `deploymentId` is set and prefer was not explicit
/// - `prefer` included when explicitly set
final class RoutingClientBodyTests: XCTestCase {

    private let testCapabilities = RoutingDeviceCapabilities(
        platform: "ios",
        model: "iPhone17,1",
        totalMemoryMb: 8192,
        gpuAvailable: true,
        npuAvailable: true,
        supportedRuntimes: ["coreml", "metal"]
    )

    // MARK: - Body Shape Tests

    func testDeploymentIdPresentInBody() throws {
        let request = RoutingRequest(
            modelId: "test-model",
            modelParams: 0,
            modelSizeMb: 0,
            deviceCapabilities: testCapabilities,
            prefer: nil,
            deploymentId: "dep_abc123"
        )

        let body = try encodeAndParse(request)
        XCTAssertEqual(body["deployment_id"] as? String, "dep_abc123")
        XCTAssertEqual(body["model_id"] as? String, "test-model")
    }

    func testPreferOmittedWhenNil() throws {
        let request = RoutingRequest(
            modelId: "test-model",
            modelParams: 0,
            modelSizeMb: 0,
            deviceCapabilities: testCapabilities,
            prefer: nil,
            deploymentId: "dep_abc123"
        )

        let body = try encodeAndParse(request)
        XCTAssertNil(body["prefer"], "prefer should be absent when nil")
        XCTAssertEqual(body["deployment_id"] as? String, "dep_abc123")
    }

    func testPreferPresentWhenSet() throws {
        let request = RoutingRequest(
            modelId: "test-model",
            modelParams: 0,
            modelSizeMb: 0,
            deviceCapabilities: testCapabilities,
            prefer: "device",
            deploymentId: "dep_abc123"
        )

        let body = try encodeAndParse(request)
        XCTAssertEqual(body["prefer"] as? String, "device")
        XCTAssertEqual(body["deployment_id"] as? String, "dep_abc123")
    }

    func testDeploymentIdOmittedWhenNil() throws {
        let request = RoutingRequest(
            modelId: "test-model",
            modelParams: 0,
            modelSizeMb: 0,
            deviceCapabilities: testCapabilities,
            prefer: "fastest",
            deploymentId: nil
        )

        let body = try encodeAndParse(request)
        XCTAssertEqual(body["prefer"] as? String, "fastest")
        XCTAssertNil(body["deployment_id"], "deployment_id should be absent when nil")
    }

    // MARK: - Config preferExplicit integration

    func testConfigOmitsPreferWhenDeploymentIdSetAndNotExplicit() {
        let config = RoutingConfig(
            serverURL: URL(string: "https://api.octomil.com")!,
            apiKey: "key",
            prefer: .fastest,
            preferExplicit: false,
            deploymentId: "dep_abc"
        )

        // Simulate what RoutingClient.route() does
        let preferValue: String? = (config.deploymentId != nil && !config.preferExplicit) ? nil : config.prefer.rawValue
        XCTAssertNil(preferValue, "prefer should be nil when deploymentId set and not explicit")
        XCTAssertEqual(config.deploymentId, "dep_abc")
    }

    func testConfigIncludesPreferWhenExplicit() {
        let config = RoutingConfig(
            serverURL: URL(string: "https://api.octomil.com")!,
            apiKey: "key",
            prefer: .device,
            preferExplicit: true,
            deploymentId: "dep_abc"
        )

        let preferValue: String? = (config.deploymentId != nil && !config.preferExplicit) ? nil : config.prefer.rawValue
        XCTAssertEqual(preferValue, "device")
    }

    func testConfigIncludesPreferWhenNoDeploymentId() {
        let config = RoutingConfig(
            serverURL: URL(string: "https://api.octomil.com")!,
            apiKey: "key",
            prefer: .cloud,
            preferExplicit: false,
            deploymentId: nil
        )

        let preferValue: String? = (config.deploymentId != nil && !config.preferExplicit) ? nil : config.prefer.rawValue
        XCTAssertEqual(preferValue, "cloud")
    }

    // MARK: - Helpers

    private func encodeAndParse(_ request: RoutingRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

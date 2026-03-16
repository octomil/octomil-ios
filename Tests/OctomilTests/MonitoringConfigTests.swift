import XCTest
@testable import Octomil

final class MonitoringConfigTests: XCTestCase {

    func testEnabledStaticProperty() {
        let config = MonitoringConfig.enabled
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.heartbeatInterval, 300)
    }

    func testDisabledStaticProperty() {
        let config = MonitoringConfig.disabled
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.heartbeatInterval, 300)
    }

    func testCustomInit() {
        let config = MonitoringConfig(enabled: true, heartbeatInterval: 60)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.heartbeatInterval, 60)
    }

    func testDefaultHeartbeatInterval() {
        let config = MonitoringConfig()
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.heartbeatInterval, 300)
    }
}

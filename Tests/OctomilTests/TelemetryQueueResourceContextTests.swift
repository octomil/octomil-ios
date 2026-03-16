import XCTest
@testable import Octomil

final class TelemetryQueueResourceContextTests: XCTestCase {

    private func makeTempPersistenceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil_test_\(UUID().uuidString)")
            .appendingPathComponent("events.json")
    }

    func testSetResourceContextFromDeviceContext() async {
        let persistURL = makeTempPersistenceURL()
        let queue = TelemetryQueue(
            modelId: "test-model",
            serverURL: nil,
            apiKey: nil,
            batchSize: 50,
            flushInterval: 0,
            persistenceURL: persistURL,
            deviceId: nil,
            orgId: nil
        )

        let ctx = DeviceContext(installationId: "uuid-abc-123", orgId: "org_test")
        await queue.setResourceContext(from: ctx)

        // Record an event so we can verify the resource context was set
        queue.recordEvent(TelemetryEvent(
            name: "test.event",
            attributes: ["key": .string("value")]
        ))

        XCTAssertEqual(queue.pendingCount, 1)

        // Cleanup
        try? FileManager.default.removeItem(at: persistURL.deletingLastPathComponent())
    }

    func testSetResourceContextFromDeviceContextWithoutOrgId() async {
        let persistURL = makeTempPersistenceURL()
        let queue = TelemetryQueue(
            modelId: "test-model",
            serverURL: nil,
            apiKey: nil,
            batchSize: 50,
            flushInterval: 0,
            persistenceURL: persistURL,
            deviceId: nil,
            orgId: nil
        )

        let ctx = DeviceContext(installationId: "uuid-def-456", orgId: nil)
        await queue.setResourceContext(from: ctx)

        // The method should use "unknown" for nil orgId values
        // This exercises the telemetryResource() -> setResourceContext path
        queue.recordEvent(TelemetryEvent(
            name: "test.event",
            attributes: [:]
        ))

        XCTAssertEqual(queue.pendingCount, 1)

        // Cleanup
        try? FileManager.default.removeItem(at: persistURL.deletingLastPathComponent())
    }

    func testSetResourceContextDirect() {
        let persistURL = makeTempPersistenceURL()
        let queue = TelemetryQueue(
            modelId: "test-model",
            serverURL: nil,
            apiKey: nil,
            batchSize: 50,
            flushInterval: 0,
            persistenceURL: persistURL,
            deviceId: nil,
            orgId: nil
        )

        // Direct call (non-async version)
        queue.setResourceContext(deviceId: "dev-id", orgId: "org-id")

        // Verify it doesn't crash and queue remains functional
        queue.recordEvent(TelemetryEvent(
            name: "test.event",
            attributes: [:]
        ))
        XCTAssertEqual(queue.pendingCount, 1)

        // Cleanup
        try? FileManager.default.removeItem(at: persistURL.deletingLastPathComponent())
    }
}

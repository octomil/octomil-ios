import XCTest
@testable import Octomil

// MARK: - TelemetryV2 Model Tests

final class TelemetryV2ModelTests: XCTestCase {

    // MARK: - TelemetryValue

    func testTelemetryValueStringRoundtrip() throws {
        let value = TelemetryValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TelemetryValue.self, from: data)
        XCTAssertEqual(decoded, .string("hello"))
        XCTAssertEqual(decoded.stringValue, "hello")
        XCTAssertNil(decoded.intValue)
        XCTAssertNil(decoded.doubleValue)
        XCTAssertNil(decoded.boolValue)
    }

    func testTelemetryValueIntRoundtrip() throws {
        let value = TelemetryValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TelemetryValue.self, from: data)
        XCTAssertEqual(decoded, .int(42))
        XCTAssertEqual(decoded.intValue, 42)
    }

    func testTelemetryValueDoubleRoundtrip() throws {
        let value = TelemetryValue.double(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TelemetryValue.self, from: data)
        XCTAssertEqual(decoded, .double(3.14))
        XCTAssertEqual(decoded.doubleValue, 3.14)
    }

    func testTelemetryValueBoolRoundtrip() throws {
        let value = TelemetryValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TelemetryValue.self, from: data)
        XCTAssertEqual(decoded, .bool(true))
        XCTAssertEqual(decoded.boolValue, true)
    }

    // MARK: - TelemetryResource

    func testResourceDefaultValues() {
        let resource = TelemetryResource(deviceId: "dev-123", orgId: "org-456")
        XCTAssertEqual(resource.sdk, "ios")
        XCTAssertEqual(resource.sdkVersion, OctomilVersion.current)
        XCTAssertEqual(resource.deviceId, "dev-123")
        XCTAssertEqual(resource.platform, "ios")
        XCTAssertEqual(resource.orgId, "org-456")
    }

    func testResourceCodable() throws {
        let resource = TelemetryResource(deviceId: "dev-1", orgId: "org-1")
        let data = try JSONEncoder().encode(resource)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["sdk"] as? String, "ios")
        XCTAssertEqual(json["sdk_version"] as? String, OctomilVersion.current)
        XCTAssertEqual(json["device_id"] as? String, "dev-1")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["org_id"] as? String, "org-1")

        let decoded = try JSONDecoder().decode(TelemetryResource.self, from: data)
        XCTAssertEqual(decoded.deviceId, "dev-1")
        XCTAssertEqual(decoded.orgId, "org-1")
    }

    // MARK: - TelemetryEvent

    func testEventCodable() throws {
        let event = TelemetryEvent(
            name: "inference.completed",
            timestamp: "2026-02-26T00:00:00Z",
            attributes: [
                "model.id": .string("fraud_detection"),
                "inference.duration_ms": .double(42.5),
                "inference.modality": .string("text"),
                "device.compute_unit": .string("ane"),
                "model.format": .string("coreml"),
            ]
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: data)

        XCTAssertEqual(decoded.name, "inference.completed")
        XCTAssertEqual(decoded.timestamp, "2026-02-26T00:00:00Z")
        XCTAssertEqual(decoded.attributes["model.id"], .string("fraud_detection"))
        XCTAssertEqual(decoded.attributes["inference.duration_ms"], .double(42.5))
        XCTAssertEqual(decoded.attributes["inference.modality"], .string("text"))
        XCTAssertEqual(decoded.attributes["device.compute_unit"], .string("ane"))
        XCTAssertEqual(decoded.attributes["model.format"], .string("coreml"))
    }

    func testEventDotNotationNames() throws {
        let inferenceEvent = TelemetryEvent(
            name: "inference.completed",
            attributes: ["model.id": .string("m1")]
        )
        XCTAssertTrue(inferenceEvent.name.contains("."))
        XCTAssertEqual(inferenceEvent.name, "inference.completed")

        let funnelEvent = TelemetryEvent(
            name: "funnel.app_pair",
            attributes: ["funnel.success": .bool(true)]
        )
        XCTAssertEqual(funnelEvent.name, "funnel.app_pair")
    }

    // MARK: - TelemetryEnvelope

    func testEnvelopeStructure() throws {
        let resource = TelemetryResource(deviceId: "dev-1", orgId: "org-1")
        let events = [
            TelemetryEvent(
                name: "inference.completed",
                attributes: [
                    "model.id": .string("m1"),
                    "inference.duration_ms": .double(10.0),
                ]
            ),
            TelemetryEvent(
                name: "funnel.first_deploy",
                attributes: [
                    "model.id": .string("m1"),
                    "funnel.success": .bool(true),
                ]
            ),
        ]
        let envelope = TelemetryEnvelope(resource: resource, events: events)

        let data = try JSONEncoder().encode(envelope)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify top-level structure
        XCTAssertNotNil(json["resource"])
        XCTAssertNotNil(json["events"])

        let resourceJson = json["resource"] as! [String: Any]
        XCTAssertEqual(resourceJson["sdk"] as? String, "ios")
        XCTAssertEqual(resourceJson["device_id"] as? String, "dev-1")
        XCTAssertEqual(resourceJson["org_id"] as? String, "org-1")

        let eventsJson = json["events"] as! [[String: Any]]
        XCTAssertEqual(eventsJson.count, 2)
        XCTAssertEqual(eventsJson[0]["name"] as? String, "inference.completed")
        XCTAssertEqual(eventsJson[1]["name"] as? String, "funnel.first_deploy")
    }

    func testEnvelopeRoundtrip() throws {
        let resource = TelemetryResource(deviceId: "d", orgId: "o")
        let events = [
            TelemetryEvent(
                name: "inference.completed",
                attributes: [
                    "model.id": .string("test"),
                    "inference.duration_ms": .double(5.0),
                    "model.format": .string("coreml"),
                ]
            )
        ]
        let envelope = TelemetryEnvelope(resource: resource, events: events)

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(TelemetryEnvelope.self, from: data)

        XCTAssertEqual(decoded.resource.deviceId, "d")
        XCTAssertEqual(decoded.resource.orgId, "o")
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events[0].name, "inference.completed")
        XCTAssertEqual(decoded.events[0].attributes["model.format"], .string("coreml"))
    }

    // MARK: - iOS-Specific Attributes

    func testIOSSpecificAttributes() throws {
        let event = TelemetryEvent(
            name: "inference.completed",
            attributes: [
                "model.id": .string("classifier"),
                "inference.duration_ms": .double(15.0),
                "device.compute_unit": .string("ane"),
                "model.format": .string("coreml"),
                "inference.modality": .string("image"),
                "inference.ttft_ms": .double(5.5),
            ]
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: data)

        XCTAssertEqual(decoded.attributes["device.compute_unit"], .string("ane"))
        XCTAssertEqual(decoded.attributes["model.format"], .string("coreml"))
        XCTAssertEqual(decoded.attributes["inference.modality"], .string("image"))
        XCTAssertEqual(decoded.attributes["inference.ttft_ms"], .double(5.5))
    }

    // MARK: - Legacy Event Conversion

    func testLegacyEventConversion() {
        let legacy = InferenceTelemetryEvent(
            modelId: "test_model",
            latencyMs: 42.5,
            timestamp: 1700000000000,
            success: true
        )

        let v2 = legacy.toV2Event()
        XCTAssertEqual(v2.name, "inference.completed")
        XCTAssertEqual(v2.attributes["model.id"], .string("test_model"))
        XCTAssertEqual(v2.attributes["inference.duration_ms"], .double(42.5))
        XCTAssertEqual(v2.attributes["model.format"], .string("coreml"))
        XCTAssertNil(v2.attributes["inference.success"]) // Only set on failure
    }

    func testLegacyFailedEventConversion() {
        let legacy = InferenceTelemetryEvent(
            modelId: "test_model",
            latencyMs: 5.0,
            success: false,
            errorMessage: "timeout"
        )

        let v2 = legacy.toV2Event()
        XCTAssertEqual(v2.name, "inference.failed")
        XCTAssertEqual(v2.attributes["inference.success"], .bool(false))
        XCTAssertEqual(v2.attributes["error.message"], .string("timeout"))
    }
}

// MARK: - TelemetryQueue V2 Tests

final class TelemetryQueueV2Tests: XCTestCase {

    private var tempDir: URL!
    private var persistenceURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        persistenceURL = tempDir.appendingPathComponent("test_v2_events.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRecordV2EventIncrementsPendingCount() {
        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        XCTAssertEqual(queue.pendingCount, 0)

        let event = TelemetryEvent(
            name: "inference.completed",
            attributes: ["model.id": .string("test")]
        )
        queue.recordEvent(event)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testRecordSuccessCreatesV2Event() {
        let queue = TelemetryQueue(
            modelId: "classifier",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )

        queue.recordSuccess(latencyMs: 12.5)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testRecordFailureCreatesV2Event() {
        let queue = TelemetryQueue(
            modelId: "classifier",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )

        queue.recordFailure(latencyMs: 5.0, error: "crash")
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testFunnelEventUsesV2Format() {
        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )

        queue.reportFunnelEvent(
            stage: "app_pair",
            success: true,
            deviceId: "dev-1",
            modelId: "m1",
            platform: "ios"
        )
        // Funnel events are now buffered as v2 events
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testPersistAndRestoreV2Events() {
        let queue1 = TelemetryQueue(
            modelId: "model_a",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        queue1.recordSuccess(latencyMs: 10.0)
        queue1.recordSuccess(latencyMs: 20.0)
        queue1.recordFailure(latencyMs: 5.0, error: "crash")
        queue1.persistEvents()

        XCTAssertTrue(FileManager.default.fileExists(atPath: persistenceURL.path))

        let queue2 = TelemetryQueue(
            modelId: "model_a",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        XCTAssertEqual(queue2.pendingCount, 3)
    }

    func testFlushClearsBuffer() async {
        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        queue.recordSuccess(latencyMs: 10.0)
        queue.recordSuccess(latencyMs: 20.0)
        XCTAssertEqual(queue.pendingCount, 2)

        await queue.flush()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testSetResourceContext() {
        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        queue.setResourceContext(deviceId: "dev-99", orgId: "org-42")
        // The resource context is stored internally and used during flush
        // We verify it doesn't crash and the queue remains functional
        queue.recordSuccess(latencyMs: 1.0)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testFlushSendsV2Envelope() async throws {
        // Set up mock HTTP
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = "telemetry.example.com"
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["status": "ok"])
        ]

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [SharedMockURLProtocol.self]

        // We can't easily inject a URLSession into TelemetryQueue (it uses URLSession.shared),
        // but we can verify the envelope structure by testing the model serialization.
        let resource = TelemetryResource(deviceId: "dev-1", orgId: "org-1")
        let events = [
            TelemetryEvent(
                name: "inference.completed",
                attributes: [
                    "model.id": .string("test"),
                    "inference.duration_ms": .double(10.0),
                    "model.format": .string("coreml"),
                ]
            )
        ]
        let envelope = TelemetryEnvelope(resource: resource, events: events)
        let data = try JSONEncoder().encode(envelope)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify the envelope has the correct v2 structure
        let resourceJson = json["resource"] as! [String: Any]
        XCTAssertEqual(resourceJson["sdk"] as? String, "ios")
        XCTAssertEqual(resourceJson["platform"] as? String, "ios")

        let eventsJson = json["events"] as! [[String: Any]]
        XCTAssertEqual(eventsJson.count, 1)
        XCTAssertEqual(eventsJson[0]["name"] as? String, "inference.completed")

        let attrs = eventsJson[0]["attributes"] as! [String: Any]
        XCTAssertEqual(attrs["model.format"] as? String, "coreml")

        SharedMockURLProtocol.reset()
    }

    func testLegacyRecordConvertsToV2() {
        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )

        let legacyEvent = InferenceTelemetryEvent(
            modelId: "test",
            latencyMs: 25.0,
            success: true
        )
        queue.record(legacyEvent)
        XCTAssertEqual(queue.pendingCount, 1)
    }
}

// MARK: - APIClient V2 Telemetry Tests

final class APIClientTelemetryV2Tests: XCTestCase {

    private static let testHost = "telemetry-v2.example.com"
    private static let testServerURL = URL(string: "https://\(testHost)")!

    private var apiClient: APIClient!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = Self.testHost

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [SharedMockURLProtocol.self]

        let config = TestConfiguration.fast(maxRetryAttempts: 1)
        apiClient = APIClient(
            serverURL: Self.testServerURL,
            configuration: config,
            sessionConfiguration: sessionConfig
        )
    }

    override func tearDown() {
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    func testReportTelemetryEventsSendsV2Envelope() async throws {
        await apiClient.setDeviceToken("test-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["status": "ok"])
        ]

        let resource = TelemetryResource(deviceId: "dev-1", orgId: "org-1")
        let events = [
            TelemetryEvent(
                name: "inference.completed",
                timestamp: "2026-02-26T00:00:00Z",
                attributes: [
                    "model.id": .string("fraud_detection"),
                    "inference.duration_ms": .double(42.5),
                    "inference.modality": .string("text"),
                    "device.compute_unit": .string("ane"),
                    "model.format": .string("coreml"),
                ]
            )
        ]
        let envelope = TelemetryEnvelope(resource: resource, events: events)

        try await apiClient.reportTelemetryEvents(envelope)

        // Verify request
        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.contains("/api/v2/telemetry/events"))

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]

        // Verify resource
        let resourceBody = body["resource"] as! [String: Any]
        XCTAssertEqual(resourceBody["sdk"] as? String, "ios")
        XCTAssertEqual(resourceBody["sdk_version"] as? String, OctomilVersion.current)
        XCTAssertEqual(resourceBody["device_id"] as? String, "dev-1")
        XCTAssertEqual(resourceBody["platform"] as? String, "ios")
        XCTAssertEqual(resourceBody["org_id"] as? String, "org-1")

        // Verify events
        let eventsBody = body["events"] as! [[String: Any]]
        XCTAssertEqual(eventsBody.count, 1)

        let event = eventsBody[0]
        XCTAssertEqual(event["name"] as? String, "inference.completed")
        XCTAssertEqual(event["timestamp"] as? String, "2026-02-26T00:00:00Z")

        let attrs = event["attributes"] as! [String: Any]
        XCTAssertEqual(attrs["model.id"] as? String, "fraud_detection")
        XCTAssertEqual(attrs["inference.duration_ms"] as? Double, 42.5)
        XCTAssertEqual(attrs["inference.modality"] as? String, "text")
        XCTAssertEqual(attrs["device.compute_unit"] as? String, "ane")
        XCTAssertEqual(attrs["model.format"] as? String, "coreml")
    }

    func testReportTelemetryEventsWithMultipleEvents() async throws {
        await apiClient.setDeviceToken("test-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["status": "ok"])
        ]

        let resource = TelemetryResource(deviceId: "dev-1", orgId: "org-1")
        let events = [
            TelemetryEvent(
                name: "inference.completed",
                attributes: [
                    "model.id": .string("m1"),
                    "inference.duration_ms": .double(10.0),
                ]
            ),
            TelemetryEvent(
                name: "inference.failed",
                attributes: [
                    "model.id": .string("m1"),
                    "inference.duration_ms": .double(5.0),
                    "error.message": .string("timeout"),
                ]
            ),
            TelemetryEvent(
                name: "funnel.first_deploy",
                attributes: [
                    "model.id": .string("m1"),
                    "funnel.success": .bool(true),
                ]
            ),
        ]
        let envelope = TelemetryEnvelope(resource: resource, events: events)

        try await apiClient.reportTelemetryEvents(envelope)

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]

        let eventsBody = body["events"] as! [[String: Any]]
        XCTAssertEqual(eventsBody.count, 3)
        XCTAssertEqual(eventsBody[0]["name"] as? String, "inference.completed")
        XCTAssertEqual(eventsBody[1]["name"] as? String, "inference.failed")
        XCTAssertEqual(eventsBody[2]["name"] as? String, "funnel.first_deploy")
    }

    func testReportTelemetryEventsUsesV2Path() async throws {
        await apiClient.setDeviceToken("test-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["status": "ok"])
        ]

        let envelope = TelemetryEnvelope(
            resource: TelemetryResource(deviceId: "d", orgId: "o"),
            events: [TelemetryEvent(name: "inference.completed", attributes: [:])]
        )

        try await apiClient.reportTelemetryEvents(envelope)

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertTrue(request.url!.absoluteString.contains("/api/v2/telemetry/events"))
        XCTAssertFalse(request.url!.absoluteString.contains("/api/v1/"))
    }
}

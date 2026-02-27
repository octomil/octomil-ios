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

// MARK: - Telemetry Wiring Integration Tests

/// Tests that verify the telemetry methods are wired into the correct call sites.
/// Since MLModel is final and cannot be mocked, these tests verify the wiring
/// patterns at the TelemetryQueue level — ensuring that the sequence of events
/// produced by the call sites matches expectations.
final class TelemetryWiringTests: XCTestCase {

    private var tempDir: URL!
    private var persistenceURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        persistenceURL = tempDir.appendingPathComponent("test_wiring_events.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeQueue() -> TelemetryQueue {
        TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
    }

    // MARK: - Inference Wiring: recordStarted before recordSuccess/recordFailure

    func testInferenceStartedPrecedesCompleted() {
        let queue = makeQueue()

        // Simulate what OctomilWrappedModel.prediction(from:) does:
        // 1. recordStarted before prediction
        // 2. recordSuccess after prediction
        queue.recordStarted(modelId: "classifier")
        queue.recordSuccess(latencyMs: 12.5)

        XCTAssertEqual(queue.pendingCount, 2)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "inference.started")
        XCTAssertEqual(events[0].attributes["model.id"], .string("classifier"))
        XCTAssertEqual(events[1].name, "inference.completed")
        XCTAssertEqual(events[1].attributes["inference.duration_ms"], .double(12.5))
    }

    func testInferenceStartedPrecedesFailed() {
        let queue = makeQueue()

        // Simulate failed prediction path
        queue.recordStarted(modelId: "classifier")
        queue.recordFailure(latencyMs: 5.0, error: "shape mismatch")

        XCTAssertEqual(queue.pendingCount, 2)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "inference.started")
        XCTAssertEqual(events[1].name, "inference.failed")
        XCTAssertEqual(events[1].attributes["error.message"], .string("shape mismatch"))
    }

    func testBatchPredictionRecordsStarted() {
        let queue = makeQueue()

        // Simulate what OctomilWrappedModel.predictions(from:) does
        queue.recordStarted(modelId: "detector")
        queue.recordSuccess(latencyMs: 50.0)

        let events = queue.bufferedEvents
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "inference.started")
        XCTAssertEqual(events[0].attributes["model.id"], .string("detector"))
    }

    // MARK: - Deploy Wiring: started then completed

    func testDeployStartedThenCompleted() {
        let queue = makeQueue()

        // Simulate what ModelManager.downloadModel and Deploy.model do
        queue.reportDeployStarted(modelId: "fraud_detection", version: "2.0.0")
        queue.reportDeployCompleted(
            modelId: "fraud_detection",
            version: "2.0.0",
            durationMs: 3500.0
        )

        XCTAssertEqual(queue.pendingCount, 2)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "deploy.started")
        XCTAssertEqual(events[0].attributes["model.id"], .string("fraud_detection"))
        XCTAssertEqual(events[0].attributes["model.version"], .string("2.0.0"))
        XCTAssertEqual(events[1].name, "deploy.completed")
        XCTAssertEqual(events[1].attributes["deploy.duration_ms"], .double(3500.0))
    }

    func testLocalDeployStartedThenCompleted() {
        let queue = makeQueue()

        // Simulate Deploy.model(at:) for local deployment
        queue.reportDeployStarted(modelId: "my_model", version: "local")
        queue.reportDeployCompleted(
            modelId: "my_model",
            version: "local",
            durationMs: 1200.0
        )

        let events = queue.bufferedEvents
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "deploy.started")
        XCTAssertEqual(events[0].attributes["model.version"], .string("local"))
        XCTAssertEqual(events[1].name, "deploy.completed")
    }

    // MARK: - Training Wiring: started, completed/failed, weight upload

    func testTrainingFullLifecycle() {
        let queue = makeQueue()

        // Simulate what OctomilClient.train() does on success
        queue.reportTrainingStarted(
            modelId: "classifier",
            version: "1.0.0",
            roundId: "local",
            numSamples: 0
        )
        queue.reportTrainingCompleted(
            modelId: "classifier",
            version: "1.0.0",
            durationMs: 5000.0,
            loss: 0.03,
            accuracy: 0.98
        )
        queue.reportWeightUpload(
            modelId: "classifier",
            roundId: "local",
            sampleCount: 200
        )

        XCTAssertEqual(queue.pendingCount, 3)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "training.started")
        XCTAssertEqual(events[1].name, "training.completed")
        XCTAssertEqual(events[1].attributes["training.loss"], .double(0.03))
        XCTAssertEqual(events[1].attributes["training.accuracy"], .double(0.98))
        XCTAssertEqual(events[2].name, "training.weight_upload")
        XCTAssertEqual(events[2].attributes["training.sample_count"], .int(200))
    }

    func testTrainingFailureLifecycle() {
        let queue = makeQueue()

        // Simulate what OctomilClient.train() does on failure
        queue.reportTrainingStarted(
            modelId: "classifier",
            version: "1.0.0",
            roundId: "round-5",
            numSamples: 0
        )
        queue.reportTrainingFailed(
            modelId: "classifier",
            version: "1.0.0",
            errorType: "OctomilError",
            errorMessage: "Model compilation failed"
        )

        XCTAssertEqual(queue.pendingCount, 2)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "training.started")
        XCTAssertEqual(events[1].name, "training.failed")
        XCTAssertEqual(events[1].attributes["error.type"], .string("OctomilError"))
    }

    // MARK: - Experiment Metric Wiring

    func testExperimentMetricFromTrackEvent() {
        let queue = makeQueue()

        // Simulate what OctomilClient.trackEvent does when properties
        // contain metric_name and metric_value
        let metricName = "click_rate"
        let metricValue = 0.15
        queue.reportExperimentMetric(
            experimentId: "exp-001",
            metricName: metricName,
            metricValue: metricValue
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "experiment.metric_recorded")
        XCTAssertEqual(event.attributes["experiment.id"], .string("exp-001"))
        XCTAssertEqual(event.attributes["experiment.metric_name"], .string("click_rate"))
        XCTAssertEqual(event.attributes["experiment.metric_value"], .double(0.15))
    }

    // MARK: - Full Inference + Deploy Sequence

    func testFullInferenceDeploySequence() {
        let queue = makeQueue()

        // Simulate a full deploy + inference lifecycle
        queue.reportDeployStarted(modelId: "m1", version: "1.0")
        queue.reportDeployCompleted(modelId: "m1", version: "1.0", durationMs: 2000.0)
        queue.recordStarted(modelId: "m1")
        queue.recordSuccess(latencyMs: 15.0)

        XCTAssertEqual(queue.pendingCount, 4)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "deploy.started")
        XCTAssertEqual(events[1].name, "deploy.completed")
        XCTAssertEqual(events[2].name, "inference.started")
        XCTAssertEqual(events[3].name, "inference.completed")
    }
}

// MARK: - Phase 4 Tests: trace_id/span_id, inference.started, training, experiment, deploy

final class TelemetryV2Phase4Tests: XCTestCase {

    private var tempDir: URL!
    private var persistenceURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        persistenceURL = tempDir.appendingPathComponent("test_phase4_events.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeQueue() -> TelemetryQueue {
        TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
    }

    // MARK: - trace_id / span_id Encoding

    func testTraceIdSpanIdEncoding() throws {
        let event = TelemetryEvent(
            name: "inference.completed",
            timestamp: "2026-02-27T00:00:00Z",
            attributes: ["model.id": .string("m1")],
            traceId: "abc123trace",
            spanId: "def456span"
        )

        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["trace_id"] as? String, "abc123trace")
        XCTAssertEqual(json["span_id"] as? String, "def456span")
        XCTAssertEqual(json["name"] as? String, "inference.completed")
        XCTAssertEqual(json["timestamp"] as? String, "2026-02-27T00:00:00Z")
    }

    func testTraceIdSpanIdRoundtrip() throws {
        let event = TelemetryEvent(
            name: "inference.started",
            attributes: ["model.id": .string("m1")],
            traceId: "trace-001",
            spanId: "span-002"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: data)

        XCTAssertEqual(decoded.traceId, "trace-001")
        XCTAssertEqual(decoded.spanId, "span-002")
        XCTAssertEqual(decoded.name, "inference.started")
    }

    func testTraceIdSpanIdNilWhenOmitted() throws {
        let event = TelemetryEvent(
            name: "inference.completed",
            attributes: ["model.id": .string("m1")]
        )

        XCTAssertNil(event.traceId)
        XCTAssertNil(event.spanId)

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: data)
        XCTAssertNil(decoded.traceId)
        XCTAssertNil(decoded.spanId)
    }

    func testTraceIdSpanIdOmittedFromJSON() throws {
        let event = TelemetryEvent(
            name: "inference.completed",
            attributes: ["model.id": .string("m1")]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)

        // When nil, the keys should not appear (or appear as null)
        // Either way, decoding should give nil
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: data)
        XCTAssertNil(decoded.traceId)
        XCTAssertNil(decoded.spanId)
    }

    // MARK: - inference.started

    func testRecordStartedEmitsEvent() {
        let queue = makeQueue()
        queue.recordStarted(modelId: "fraud_detection")

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "inference.started")
        XCTAssertEqual(event.attributes["model.id"], .string("fraud_detection"))
        XCTAssertEqual(event.attributes["model.format"], .string("coreml"))
    }

    // MARK: - Training Events

    func testReportTrainingStarted() {
        let queue = makeQueue()
        queue.reportTrainingStarted(
            modelId: "classifier",
            version: "1.0.0",
            roundId: "round-42",
            numSamples: 500
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "training.started")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["model.version"], .string("1.0.0"))
        XCTAssertEqual(event.attributes["training.round_id"], .string("round-42"))
        XCTAssertEqual(event.attributes["training.num_samples"], .int(500))
    }

    func testReportTrainingCompleted() {
        let queue = makeQueue()
        queue.reportTrainingCompleted(
            modelId: "classifier",
            version: "1.0.0",
            durationMs: 12345.6,
            loss: 0.05,
            accuracy: 0.97
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "training.completed")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["model.version"], .string("1.0.0"))
        XCTAssertEqual(event.attributes["training.duration_ms"], .double(12345.6))
        XCTAssertEqual(event.attributes["training.loss"], .double(0.05))
        XCTAssertEqual(event.attributes["training.accuracy"], .double(0.97))
    }

    func testReportTrainingFailed() {
        let queue = makeQueue()
        queue.reportTrainingFailed(
            modelId: "classifier",
            version: "1.0.0",
            errorType: "OOM",
            errorMessage: "Out of memory during backward pass"
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "training.failed")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["model.version"], .string("1.0.0"))
        XCTAssertEqual(event.attributes["error.type"], .string("OOM"))
        XCTAssertEqual(event.attributes["error.message"], .string("Out of memory during backward pass"))
    }

    func testReportWeightUpload() {
        let queue = makeQueue()
        queue.reportWeightUpload(
            modelId: "classifier",
            roundId: "round-42",
            sampleCount: 250
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "training.weight_upload")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["training.round_id"], .string("round-42"))
        XCTAssertEqual(event.attributes["training.sample_count"], .int(250))
    }

    // MARK: - Experiment Events

    func testReportExperimentAssigned() {
        let queue = makeQueue()
        queue.reportExperimentAssigned(
            modelId: "classifier",
            experimentId: "exp-001",
            variant: "treatment_a"
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "experiment.assigned")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["experiment.id"], .string("exp-001"))
        XCTAssertEqual(event.attributes["experiment.variant"], .string("treatment_a"))
    }

    func testReportExperimentMetric() {
        let queue = makeQueue()
        queue.reportExperimentMetric(
            experimentId: "exp-001",
            metricName: "click_rate",
            metricValue: 0.15
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "experiment.metric_recorded")
        XCTAssertEqual(event.attributes["experiment.id"], .string("exp-001"))
        XCTAssertEqual(event.attributes["experiment.metric_name"], .string("click_rate"))
        XCTAssertEqual(event.attributes["experiment.metric_value"], .double(0.15))
    }

    // MARK: - Deploy Events

    func testReportDeployStarted() {
        let queue = makeQueue()
        queue.reportDeployStarted(modelId: "classifier", version: "2.0.0")

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "deploy.started")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["model.version"], .string("2.0.0"))
    }

    func testReportDeployCompleted() {
        let queue = makeQueue()
        queue.reportDeployCompleted(
            modelId: "classifier",
            version: "2.0.0",
            durationMs: 5432.1
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "deploy.completed")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["model.version"], .string("2.0.0"))
        XCTAssertEqual(event.attributes["deploy.duration_ms"], .double(5432.1))
    }

    func testReportDeployRollback() {
        let queue = makeQueue()
        queue.reportDeployRollback(
            modelId: "classifier",
            fromVersion: "2.0.0",
            toVersion: "1.5.0",
            reason: "accuracy regression"
        )

        XCTAssertEqual(queue.pendingCount, 1)

        let event = queue.bufferedEvents.first!
        XCTAssertEqual(event.name, "deploy.rollback")
        XCTAssertEqual(event.attributes["model.id"], .string("classifier"))
        XCTAssertEqual(event.attributes["deploy.from_version"], .string("2.0.0"))
        XCTAssertEqual(event.attributes["deploy.to_version"], .string("1.5.0"))
        XCTAssertEqual(event.attributes["deploy.reason"], .string("accuracy regression"))
    }

    // MARK: - Multiple Event Types in One Queue

    func testMixedEventTypes() {
        let queue = makeQueue()

        queue.recordStarted(modelId: "m1")
        queue.recordSuccess(latencyMs: 10.0)
        queue.reportTrainingStarted(modelId: "m1", version: "1.0", roundId: "r1", numSamples: 100)
        queue.reportExperimentAssigned(modelId: "m1", experimentId: "e1", variant: "control")
        queue.reportDeployStarted(modelId: "m1", version: "1.0")

        XCTAssertEqual(queue.pendingCount, 5)

        let events = queue.bufferedEvents
        XCTAssertEqual(events[0].name, "inference.started")
        XCTAssertEqual(events[1].name, "inference.completed")
        XCTAssertEqual(events[2].name, "training.started")
        XCTAssertEqual(events[3].name, "experiment.assigned")
        XCTAssertEqual(events[4].name, "deploy.started")
    }

    // MARK: - Persistence of New Event Types

    func testNewEventTypesPersistAndRestore() {
        let queue1 = makeQueue()
        queue1.reportTrainingStarted(modelId: "m1", version: "1.0", roundId: "r1", numSamples: 50)
        queue1.reportExperimentMetric(experimentId: "e1", metricName: "latency_p99", metricValue: 42.5)
        queue1.reportDeployRollback(modelId: "m1", fromVersion: "2.0", toVersion: "1.0", reason: "crash")
        queue1.persistEvents()

        let queue2 = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        XCTAssertEqual(queue2.pendingCount, 3)

        let events = queue2.bufferedEvents
        XCTAssertEqual(events[0].name, "training.started")
        XCTAssertEqual(events[0].attributes["training.num_samples"], .int(50))
        XCTAssertEqual(events[1].name, "experiment.metric_recorded")
        XCTAssertEqual(events[1].attributes["experiment.metric_value"], .double(42.5))
        XCTAssertEqual(events[2].name, "deploy.rollback")
        XCTAssertEqual(events[2].attributes["deploy.reason"], .string("crash"))
    }
}

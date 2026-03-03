// swiftlint:disable file_length
import XCTest
@testable import Octomil

// swiftlint:disable type_body_length
final class APIModelsTests: XCTestCase {

    // MARK: - Test Constants

    private static let testDownloadURL = "https://storage.example.com/models/fraud-v2.mlmodelc"

    // MARK: - Device Registration Tests

    func testDeviceCapabilitiesEncoding() throws {
        let capabilities = DeviceCapabilities(
            supportsTraining: true,
            coremlVersion: "5.0",
            hasNeuralEngine: true,
            maxBatchSize: 32,
            supportedFormats: ["coreml", "onnx"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["supports_training"] as? Bool, true)
        XCTAssertEqual(json["coreml_version"] as? String, "5.0")
        XCTAssertEqual(json["has_neural_engine"] as? Bool, true)
        XCTAssertEqual(json["max_batch_size"] as? Int, 32)
        XCTAssertEqual(json["supported_formats"] as? [String], ["coreml", "onnx"])
    }

    func testDeviceCapabilitiesDefaults() {
        let capabilities = DeviceCapabilities()

        XCTAssertTrue(capabilities.supportsTraining)
        XCTAssertNil(capabilities.coremlVersion)
        XCTAssertFalse(capabilities.hasNeuralEngine)
        XCTAssertNil(capabilities.maxBatchSize)
        XCTAssertNil(capabilities.supportedFormats)
    }

    func testDeviceRegistrationRequestEncoding() throws {
        let capabilities = DeviceCapabilities(
            supportsTraining: true,
            coremlVersion: "5.0",
            hasNeuralEngine: true
        )

        let request = DeviceRegistrationRequest(
            deviceIdentifier: "test-device-123",
            orgId: "test-org",
            platform: "ios",
            osVersion: nil,
            sdkVersion: nil,
            appVersion: nil,
            deviceInfo: nil,
            locale: nil,
            region: nil,
            timezone: nil,
            metadata: ["app_version": "1.0.0"],
            capabilities: capabilities
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["device_identifier"] as? String, "test-device-123")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertNotNil(json["capabilities"])
        XCTAssertNotNil(json["metadata"])
    }

    func testDeviceRegistrationResponseDecoding() throws {
        let json = """
        {
            "id": "abc-123",
            "device_identifier": "test-device",
            "org_id": "org-123",
            "status": "active",
            "registered_at": "2024-01-15T10:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let registration = try decoder.decode(DeviceRegistrationResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(registration.id, "abc-123")
        XCTAssertEqual(registration.deviceIdentifier, "test-device")
        XCTAssertEqual(registration.orgId, "org-123")
        XCTAssertEqual(registration.status, "active")
        XCTAssertNotNil(registration.registeredAt)
    }

    // MARK: - Model Metadata Tests

    func testModelMetadataDecoding() throws {
        let json = """
        {
            "model_id": "fraud-detection",
            "version": "1.2.0",
            "checksum": "abc123def456",
            "file_size": 10485760,
            "created_at": "2024-01-15T10:30:00Z",
            "format": "coreml",
            "supports_training": true,
            "description": "Fraud detection model",
            "input_schema": {"features": "float32"},
            "output_schema": {"prediction": "float32"}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let metadata = try decoder.decode(ModelMetadata.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(metadata.modelId, "fraud-detection")
        XCTAssertEqual(metadata.version, "1.2.0")
        XCTAssertEqual(metadata.checksum, "abc123def456")
        XCTAssertEqual(metadata.fileSize, 10485760)
        XCTAssertEqual(metadata.format, "coreml")
        XCTAssertTrue(metadata.supportsTraining)
        XCTAssertEqual(metadata.description, "Fraud detection model")
    }

    // MARK: - Version Resolution Tests

    func testVersionResolutionDecoding() throws {
        let json = """
        {
            "version": "2.0.0",
            "source": "rollout",
            "experiment_id": null,
            "rollout_id": 5,
            "device_bucket": 23
        }
        """

        let decoder = JSONDecoder()
        let resolution = try decoder.decode(VersionResolutionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(resolution.version, "2.0.0")
        XCTAssertEqual(resolution.source, "rollout")
        XCTAssertNil(resolution.experimentId)
        XCTAssertEqual(resolution.rolloutId, 5)
        XCTAssertEqual(resolution.deviceBucket, 23)
    }

    // MARK: - Training Config Tests

    func testTrainingConfigDefaults() {
        let config = TrainingConfig.standard

        XCTAssertEqual(config.epochs, 1)
        XCTAssertEqual(config.batchSize, 32)
        XCTAssertEqual(config.learningRate, 0.001)
        XCTAssertTrue(config.shuffle)
    }

    func testTrainingConfigCustom() {
        let config = TrainingConfig(
            epochs: 5,
            batchSize: 64,
            learningRate: 0.01,
            shuffle: false
        )

        XCTAssertEqual(config.epochs, 5)
        XCTAssertEqual(config.batchSize, 64)
        XCTAssertEqual(config.learningRate, 0.01)
        XCTAssertFalse(config.shuffle)
    }

    func testTrainingConfigEncoding() throws {
        let config = TrainingConfig(epochs: 3, batchSize: 16, learningRate: 0.005, shuffle: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["epochs"] as? Int, 3)
        XCTAssertEqual(json["batchSize"] as? Int, 16)
        XCTAssertEqual(json["learningRate"] as? Double, 0.005)
        XCTAssertEqual(json["shuffle"] as? Bool, true)
    }

    // MARK: - Tracking Event Tests

    func testTrackingEventCreation() {
        let now = Date()
        let event = TrackingEvent(
            name: "model_loaded",
            properties: ["model_id": "test", "version": "1.0.0"],
            timestamp: now
        )

        XCTAssertEqual(event.name, "model_loaded")
        XCTAssertEqual(event.properties["model_id"], "test")
        XCTAssertEqual(event.properties["version"], "1.0.0")
        XCTAssertEqual(event.timestamp, now)
    }

    func testTrackingEventDefaultTimestamp() {
        let beforeCreation = Date()
        let event = TrackingEvent(name: "test_event")
        let afterCreation = Date()

        XCTAssertGreaterThanOrEqual(event.timestamp, beforeCreation)
        XCTAssertLessThanOrEqual(event.timestamp, afterCreation)
        XCTAssertTrue(event.properties.isEmpty)
    }

    // MARK: - Heartbeat Tests

    func testHeartbeatRequestEncodingWithMetadata() throws {
        let request = HeartbeatRequest(metadata: ["available_storage_mb": "2048"])

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let metadata = json["metadata"] as? [String: String]
        XCTAssertEqual(metadata?["available_storage_mb"], "2048")
    }

    func testHeartbeatRequestEncodingWithoutMetadata() throws {
        let request = HeartbeatRequest()

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertTrue(json["metadata"] is NSNull || json["metadata"] == nil)
    }

    func testHeartbeatResponseDecoding() throws {
        let json = """
        {
            "id": "device-uuid-123",
            "device_identifier": "idfv-abc",
            "status": "active",
            "last_heartbeat": "2024-06-15T12:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(HeartbeatResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.id, "device-uuid-123")
        XCTAssertEqual(response.deviceIdentifier, "idfv-abc")
        XCTAssertEqual(response.status, "active")
        XCTAssertNotNil(response.lastHeartbeat)
    }

    // MARK: - Model Update Info Tests

    func testModelUpdateInfoDecoding() throws {
        let json = """
        {
            "new_version": "2.1.0",
            "current_version": "2.0.0",
            "is_required": true,
            "release_notes": "Bug fixes and performance improvements",
            "update_size": 5242880
        }
        """

        let decoder = JSONDecoder()
        let info = try decoder.decode(ModelUpdateInfo.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(info.newVersion, "2.1.0")
        XCTAssertEqual(info.currentVersion, "2.0.0")
        XCTAssertTrue(info.isRequired)
        XCTAssertEqual(info.releaseNotes, "Bug fixes and performance improvements")
        XCTAssertEqual(info.updateSize, 5242880)
    }

    func testModelUpdateInfoDecodingWithNullReleaseNotes() throws {
        let json = """
        {
            "new_version": "1.1.0",
            "current_version": "1.0.0",
            "is_required": false,
            "release_notes": null,
            "update_size": 1024
        }
        """

        let decoder = JSONDecoder()
        let info = try decoder.decode(ModelUpdateInfo.self, from: json.data(using: .utf8)!)

        XCTAssertFalse(info.isRequired)
        XCTAssertNil(info.releaseNotes)
    }

    // MARK: - Download URL Response Tests

    func testDownloadURLResponseDecoding() throws {
        let json = """
        {
            "url": "\(Self.testDownloadURL)",
            "expires_at": "2024-06-15T13:00:00Z",
            "checksum": "sha256:abcdef1234567890",
            "file_size": 10485760
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(DownloadURLResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.url, Self.testDownloadURL)
        XCTAssertEqual(response.checksum, "sha256:abcdef1234567890")
        XCTAssertEqual(response.fileSize, 10485760)
        XCTAssertNotNil(response.expiresAt)
    }

    // MARK: - Training Result Tests

    func testTrainingResultDecoding() throws {
        let json = """
        {
            "sample_count": 1000,
            "loss": 0.035,
            "accuracy": 0.97,
            "training_time": 12.5,
            "metrics": {"f1_score": 0.95, "precision": 0.96}
        }
        """

        let decoder = JSONDecoder()
        let result = try decoder.decode(TrainingResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.sampleCount, 1000)
        XCTAssertEqual(result.loss, 0.035)
        XCTAssertEqual(result.accuracy, 0.97)
        XCTAssertEqual(result.trainingTime, 12.5)
        XCTAssertEqual(result.metrics["f1_score"], 0.95)
        XCTAssertEqual(result.metrics["precision"], 0.96)
    }

    func testTrainingResultDecodingWithNullOptionals() throws {
        let json = """
        {
            "sample_count": 500,
            "loss": null,
            "accuracy": null,
            "training_time": 5.0,
            "metrics": {}
        }
        """

        let decoder = JSONDecoder()
        let result = try decoder.decode(TrainingResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.sampleCount, 500)
        XCTAssertNil(result.loss)
        XCTAssertNil(result.accuracy)
        XCTAssertEqual(result.trainingTime, 5.0)
        XCTAssertTrue(result.metrics.isEmpty)
    }

    // MARK: - Round Result Tests

    func testRoundResultDecoding() throws {
        let json = """
        {
            "round_id": "round-42",
            "training_result": {
                "sample_count": 200,
                "loss": 0.12,
                "accuracy": 0.88,
                "training_time": 8.0,
                "metrics": {}
            },
            "upload_succeeded": true,
            "completed_at": "2024-06-15T14:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(RoundResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.roundId, "round-42")
        XCTAssertEqual(result.trainingResult.sampleCount, 200)
        XCTAssertEqual(result.trainingResult.loss, 0.12)
        XCTAssertTrue(result.uploadSucceeded)
        XCTAssertNotNil(result.completedAt)
    }

    // MARK: - Weight Update Tests

    func testWeightUpdateEncoding() throws {
        let weightsData = Data([0x01, 0x02, 0x03, 0x04])
        let update = WeightUpdate(
            modelId: "fraud-detection",
            version: "2.0.0",
            deviceId: "device-uuid-123",
            weightsData: weightsData,
            sampleCount: 500,
            metrics: ["loss": 0.05, "accuracy": 0.98]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(update)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model_id"] as? String, "fraud-detection")
        XCTAssertEqual(json["version"] as? String, "2.0.0")
        XCTAssertEqual(json["device_id"] as? String, "device-uuid-123")
        XCTAssertEqual(json["sample_count"] as? Int, 500)
        XCTAssertNotNil(json["weights_data"])
    }

    func testWeightUpdateRoundTrip() throws {
        let weightsData = Data(repeating: 0xAB, count: 64)
        let original = WeightUpdate(
            modelId: "model-abc",
            version: "1.0.0",
            deviceId: nil,
            weightsData: weightsData,
            sampleCount: 100,
            metrics: ["loss": 0.1]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WeightUpdate.self, from: data)

        XCTAssertEqual(decoded.modelId, original.modelId)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertNil(decoded.deviceId)
        XCTAssertEqual(decoded.weightsData, original.weightsData)
        XCTAssertEqual(decoded.sampleCount, original.sampleCount)
        XCTAssertEqual(decoded.metrics["loss"], original.metrics["loss"])
    }

    // MARK: - API Error Response Tests

    func testAPIErrorResponseDecoding() throws {
        let json = """
        {"detail": "Device not found"}
        """

        let decoder = JSONDecoder()
        let error = try decoder.decode(APIErrorResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(error.detail, "Device not found")
    }

    // MARK: - TrainingConfig Encoding Round-Trip

    func testTrainingConfigRoundTrip() throws {
        let original = TrainingConfig(epochs: 10, batchSize: 128, learningRate: 0.0001, shuffle: false)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingConfig.self, from: data)

        XCTAssertEqual(decoded.epochs, original.epochs)
        XCTAssertEqual(decoded.batchSize, original.batchSize)
        XCTAssertEqual(decoded.learningRate, original.learningRate)
        XCTAssertEqual(decoded.shuffle, original.shuffle)
    }

    // MARK: - Device Group Tests

    func testDeviceGroupDecoding() throws {
        let json = """
        {
            "id": "group-uuid-1",
            "name": "beta-testers",
            "description": "Beta testing group",
            "group_type": "static",
            "is_active": true,
            "device_count": 150,
            "tags": ["beta", "ios"],
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-06-15T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let group = try decoder.decode(DeviceGroup.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(group.id, "group-uuid-1")
        XCTAssertEqual(group.name, "beta-testers")
        XCTAssertEqual(group.description, "Beta testing group")
        XCTAssertEqual(group.groupType, "static")
        XCTAssertTrue(group.isActive)
        XCTAssertEqual(group.deviceCount, 150)
        XCTAssertEqual(group.tags, ["beta", "ios"])
    }

    func testDeviceGroupsResponseDecoding() throws {
        let json = """
        {
            "groups": [
                {
                    "id": "g1",
                    "name": "group-a",
                    "description": null,
                    "group_type": "dynamic",
                    "is_active": true,
                    "device_count": 50,
                    "tags": null,
                    "created_at": "2024-01-01T00:00:00Z",
                    "updated_at": "2024-01-01T00:00:00Z"
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(DeviceGroupsResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.groups.count, 1)
        XCTAssertEqual(response.groups.first?.name, "group-a")
        XCTAssertNil(response.groups.first?.description)
        XCTAssertNil(response.groups.first?.tags)
    }

    // MARK: - AnyCodable Tests

    func testAnyCodableInt() throws {
        let json = """
        {"value": 42}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? Int, 42)
    }

    func testAnyCodableString() throws {
        let json = """
        {"value": "hello"}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? String, "hello")
    }

    func testAnyCodableDouble() throws {
        let json = """
        {"value": 3.14}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? Double, 3.14)
    }

    func testAnyCodableBool() throws {
        let json = """
        {"value": true}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? Bool, true)
    }

    func testAnyCodableNull() throws {
        let json = """
        {"value": null}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertTrue(decoded["value"]?.value is NSNull)
    }

    func testAnyCodableRoundTrip() throws {
        let original: [String: AnyCodable] = [
            "int": AnyCodable(42),
            "string": AnyCodable("hello"),
            "double": AnyCodable(3.14),
            "bool": AnyCodable(true),
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["int"]?.value as? Int, 42)
        XCTAssertEqual(decoded["string"]?.value as? String, "hello")
        XCTAssertEqual(decoded["double"]?.value as? Double, 3.14)
        XCTAssertEqual(decoded["bool"]?.value as? Bool, true)
    }

    // MARK: - DeviceInfo decoding

    func testDeviceInfoDecoding() throws {
        let json = """
        {
            "id": "dev-uuid-1",
            "device_identifier": "idfv-abc",
            "org_id": "org-1",
            "platform": "ios",
            "os_version": "17.0",
            "sdk_version": "1.0.0",
            "app_version": "2.0.0",
            "status": "active",
            "manufacturer": "Apple",
            "model": "iPhone 15",
            "cpu_architecture": "arm64",
            "gpu_available": true,
            "total_memory_mb": 6144,
            "available_storage_mb": 25600,
            "locale": "en_US",
            "region": "US",
            "timezone": "America/Los_Angeles",
            "last_heartbeat": "2026-02-09T12:00:00Z",
            "heartbeat_interval_seconds": 300,
            "capabilities": {"neural_engine": "true"},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-02-09T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(DeviceInfo.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(info.id, "dev-uuid-1")
        XCTAssertEqual(info.deviceIdentifier, "idfv-abc")
        XCTAssertEqual(info.orgId, "org-1")
        XCTAssertEqual(info.platform, "ios")
        XCTAssertEqual(info.osVersion, "17.0")
        XCTAssertEqual(info.sdkVersion, "1.0.0")
        XCTAssertEqual(info.appVersion, "2.0.0")
        XCTAssertEqual(info.status, "active")
        XCTAssertEqual(info.manufacturer, "Apple")
        XCTAssertEqual(info.model, "iPhone 15")
        XCTAssertEqual(info.cpuArchitecture, "arm64")
        XCTAssertTrue(info.gpuAvailable)
        XCTAssertEqual(info.totalMemoryMb, 6144)
        XCTAssertEqual(info.availableStorageMb, 25600)
        XCTAssertEqual(info.locale, "en_US")
        XCTAssertEqual(info.region, "US")
        XCTAssertEqual(info.timezone, "America/Los_Angeles")
        XCTAssertNotNil(info.lastHeartbeat)
        XCTAssertEqual(info.heartbeatIntervalSeconds, 300)
        XCTAssertNotNil(info.capabilities)
    }

    func testDeviceInfoDecodingWithNulls() throws {
        let json = """
        {
            "id": "dev-uuid-2",
            "device_identifier": "idfv-xyz",
            "org_id": "org-2",
            "platform": "ios",
            "os_version": null,
            "sdk_version": null,
            "app_version": null,
            "status": "inactive",
            "manufacturer": null,
            "model": null,
            "cpu_architecture": null,
            "gpu_available": false,
            "total_memory_mb": null,
            "available_storage_mb": null,
            "locale": null,
            "region": null,
            "timezone": null,
            "last_heartbeat": null,
            "heartbeat_interval_seconds": 600,
            "capabilities": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(DeviceInfo.self, from: json.data(using: .utf8)!)

        XCTAssertNil(info.osVersion)
        XCTAssertNil(info.sdkVersion)
        XCTAssertNil(info.appVersion)
        XCTAssertNil(info.manufacturer)
        XCTAssertNil(info.model)
        XCTAssertNil(info.cpuArchitecture)
        XCTAssertFalse(info.gpuAvailable)
        XCTAssertNil(info.totalMemoryMb)
        XCTAssertNil(info.lastHeartbeat)
        XCTAssertNil(info.capabilities)
        XCTAssertEqual(info.heartbeatIntervalSeconds, 600)
    }

    // MARK: - ModelVersionResponse decoding

    func testModelVersionResponseDecoding() throws {
        let json = """
        {
            "model_id": "fraud-v2",
            "version": "2.1.0",
            "checksum": "sha256:abc123",
            "size_bytes": 52428800,
            "format": "coreml",
            "description": "Improved fraud detection",
            "created_at": "2026-02-01T00:00:00Z",
            "metrics": {"accuracy": 0.95, "f1": 0.93}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ModelVersionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.modelId, "fraud-v2")
        XCTAssertEqual(response.version, "2.1.0")
        XCTAssertEqual(response.checksum, "sha256:abc123")
        XCTAssertEqual(response.sizeBytes, 52428800)
        XCTAssertEqual(response.format, "coreml")
        XCTAssertEqual(response.description, "Improved fraud detection")
        XCTAssertNotNil(response.metrics)
        XCTAssertEqual(response.metrics?["accuracy"]?.value as? Double, 0.95)
    }

    func testModelVersionResponseNullOptionals() throws {
        let json = """
        {
            "model_id": "basic",
            "version": "1.0.0",
            "checksum": "abc",
            "size_bytes": 1024,
            "format": "onnx",
            "description": null,
            "created_at": "2026-01-01T00:00:00Z",
            "metrics": null
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ModelVersionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertNil(response.description)
        XCTAssertNil(response.metrics)
    }

    // MARK: - DeviceInfoRequest encoding

    func testDeviceInfoRequestEncoding() throws {
        let request = DeviceInfoRequest(
            manufacturer: "Apple",
            model: "iPhone 15 Pro",
            cpuArchitecture: "arm64",
            gpuAvailable: true,
            totalMemoryMb: 8192,
            availableStorageMb: 50000
        )

        let data = try JSONEncoder().encode(request)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["manufacturer"] as? String, "Apple")
        XCTAssertEqual(json["model"] as? String, "iPhone 15 Pro")
        XCTAssertEqual(json["cpu_architecture"] as? String, "arm64")
        XCTAssertEqual(json["gpu_available"] as? Bool, true)
        XCTAssertEqual(json["total_memory_mb"] as? Int, 8192)
        XCTAssertEqual(json["available_storage_mb"] as? Int, 50000)
    }

    // MARK: - TrackingEvent encoding

    func testTrackingEventEncoding() throws {
        let event = TrackingEvent(
            name: "model_loaded",
            properties: ["model_id": "test"],
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["name"] as? String, "model_loaded")
        XCTAssertNotNil(json["properties"])
        XCTAssertNotNil(json["timestamp"])
    }

    // MARK: - New DTO Tests (SDK Parity)

    func testRoundAssignmentDecoding() throws {
        let json = """
        {"id":"r1","org_id":"org1","model_id":"m1","version_id":"v1","state":"active",
         "min_clients":2,"max_clients":10,"client_selection_strategy":"random",
         "aggregation_type":"fedavg","timeout_minutes":30,
         "differential_privacy":false,"secure_aggregation":false,
         "selected_client_count":0,"received_update_count":0,
         "created_at":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let round = try JSONDecoder().decode(RoundAssignment.self, from: json)
        XCTAssertEqual(round.id, "r1")
        XCTAssertEqual(round.state, "active")
        XCTAssertEqual(round.minClients, 2)
        XCTAssertFalse(round.differentialPrivacy)
    }

    func testHealthResponseDecoding() throws {
        let json = """
        {"status":"ok","version":"1.2.3","timestamp":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(HealthResponse.self, from: json)
        XCTAssertEqual(resp.status, "ok")
        XCTAssertEqual(resp.version, "1.2.3")
    }

    func testModelResponseDecoding() throws {
        let json = """
        {"id":"m1","org_id":"org1","name":"TestModel","framework":"coreml",
         "use_case":"classification","version_count":3,
         "created_at":"2026-01-01","updated_at":"2026-01-02"}
        """.data(using: .utf8)!
        let model = try JSONDecoder().decode(ModelResponse.self, from: json)
        XCTAssertEqual(model.name, "TestModel")
        XCTAssertEqual(model.versionCount, 3)
    }

    func testDevicePolicyResponseDecoding() throws {
        let json = """
        {"battery_threshold":20,"network_policy":"wifi_only"}
        """.data(using: .utf8)!
        let policy = try JSONDecoder().decode(DevicePolicyResponse.self, from: json)
        XCTAssertEqual(policy.batteryThreshold, 20)
        XCTAssertEqual(policy.networkPolicy, "wifi_only")
        XCTAssertNil(policy.samplingPolicy)
    }

    func testGradientUpdateRequestEncoding() throws {
        let req = GradientUpdateRequest(
            deviceId: "d1",
            modelId: "m1",
            version: "1.0",
            roundId: "r1",
            gradientsPath: nil,
            numSamples: 100,
            trainingTimeMs: 5000,
            metrics: GradientTrainingMetrics(loss: 0.5, accuracy: 0.9, numBatches: 10, learningRate: nil, customMetrics: nil)
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["device_id"] as? String, "d1")
        XCTAssertEqual(json["num_samples"] as? Int, 100)
    }

    func testWeightUpdateFlatEncoding() throws {
        let req = WeightUpdate(
            modelId: "m1",
            version: "1.0",
            deviceId: "d1",
            weightsData: Data([0x01, 0x02]),
            sampleCount: 50,
            metrics: ["loss": 0.1],
            dpMetadata: .init(epsilonUsed: 1.0, mechanism: "gaussian")
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["dp_epsilon_used"] as? Double, 1.0)
        XCTAssertEqual(json["dp_mechanism"] as? String, "gaussian")
        XCTAssertNil(json["dp_noise_scale"])
    }

    func testWeightUpdateNoDPEncoding() throws {
        let req = WeightUpdate(
            modelId: "m1",
            version: "1.0",
            deviceId: nil,
            weightsData: Data([0x01]),
            sampleCount: 10,
            metrics: [:]
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["dp_epsilon_used"])
        XCTAssertNil(json["dp_mechanism"])
    }

    func testHeartbeatRequestDeviceStateEncoding() throws {
        var req = HeartbeatRequest(metadata: ["key": "val"])
        req.batteryLevel = 85
        req.isCharging = true
        req.networkType = "wifi"
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["battery_level"] as? Int, 85)
        XCTAssertEqual(json["is_charging"] as? Bool, true)
        XCTAssertEqual(json["network_type"] as? String, "wifi")
    }

    func testTrackingEventVarFields() throws {
        var event = TrackingEvent(name: "train_start")
        event.deviceId = "d1"
        event.modelId = "m1"
        event.metrics = ["loss": 0.5]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["device_id"] as? String, "d1")
        XCTAssertEqual(json["model_id"] as? String, "m1")
    }

    func testDownloadURLResponseOptionalFields() throws {
        let json = """
        {"url":"https://example.com/model.mlmodel",
         "expires_at":"2026-01-01T00:00:00Z","checksum":"abc123","file_size":1024,
         "quantization":"int8","recommended_delegates":["neural_engine"],
         "input_shape":[1,28,28,1]}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(DownloadURLResponse.self, from: json)
        XCTAssertEqual(resp.url, "https://example.com/model.mlmodel")
        XCTAssertEqual(resp.quantization, "int8")
        XCTAssertEqual(resp.recommendedDelegates, ["neural_engine"])
        XCTAssertEqual(resp.inputShape, [1, 28, 28, 1])
        XCTAssertNil(resp.hasTrainingSignature)
    }
}
// swiftlint:enable type_body_length

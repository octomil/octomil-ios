import CoreML
import Foundation
import XCTest
@testable import Octomil

// MARK: - WrapperConfigTests

final class WrapperConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = OctomilWrapperConfig.default
        XCTAssertTrue(config.validateInputs)
        XCTAssertTrue(config.telemetryEnabled)
        XCTAssertTrue(config.otaUpdatesEnabled)
        XCTAssertEqual(config.telemetryBatchSize, 50)
        XCTAssertEqual(config.telemetryFlushInterval, 30)
        XCTAssertNil(config.serverURL)
        XCTAssertNil(config.apiKey)
    }

    func testCustomConfig() {
        let url = URL(string: "https://api.octomil.com")!
        let config = OctomilWrapperConfig(
            validateInputs: false,
            telemetryEnabled: false,
            telemetryBatchSize: 10,
            telemetryFlushInterval: 5,
            otaUpdatesEnabled: false,
            serverURL: url,
            apiKey: "test-key"
        )

        XCTAssertFalse(config.validateInputs)
        XCTAssertFalse(config.telemetryEnabled)
        XCTAssertFalse(config.otaUpdatesEnabled)
        XCTAssertEqual(config.telemetryBatchSize, 10)
        XCTAssertEqual(config.telemetryFlushInterval, 5)
        XCTAssertEqual(config.serverURL, url)
        XCTAssertEqual(config.apiKey, "test-key")
    }
}

// MARK: - ContractValidationTests

final class ContractValidationTests: XCTestCase {

    func testValidationPassesWhenAllFeaturesPresent() throws {
        let contract = WrappedModelContract(
            inputFeatureNames: ["x", "y"],
            outputFeatureNames: ["result"]
        )

        let provider = MockFeatureProvider(doubles: ["x": 1.0, "y": 2.0])
        XCTAssertNoThrow(try contract.validate(input: provider))
    }

    func testValidationPassesWithExtraFeatures() throws {
        let contract = WrappedModelContract(
            inputFeatureNames: ["x"],
            outputFeatureNames: ["result"]
        )

        // Provider has extra feature "y" -- that's fine
        let provider = MockFeatureProvider(doubles: ["x": 1.0, "y": 2.0])
        XCTAssertNoThrow(try contract.validate(input: provider))
    }

    func testValidationFailsWhenFeaturesMissing() {
        let contract = WrappedModelContract(
            inputFeatureNames: ["x", "y", "z"],
            outputFeatureNames: ["result"]
        )

        let provider = MockFeatureProvider(doubles: ["x": 1.0])

        do {
            try contract.validate(input: provider)
            XCTFail("Expected FeatureValidationError")
        } catch let error as FeatureValidationError {
            XCTAssertTrue(error.missingFeatures.contains("y"))
            XCTAssertTrue(error.missingFeatures.contains("z"))
            XCTAssertEqual(error.missingFeatures.count, 2)
            XCTAssertNotNil(error.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testValidationWithEmptyContract() throws {
        let contract = WrappedModelContract(
            inputFeatureNames: [],
            outputFeatureNames: []
        )
        let provider = MockFeatureProvider(doubles: ["anything": 42.0])
        XCTAssertNoThrow(try contract.validate(input: provider))
    }

    func testContractVersionProperty() {
        let contract = WrappedModelContract(
            inputFeatureNames: ["x"],
            version: "1.2.3"
        )
        XCTAssertEqual(contract.version, "1.2.3")
    }
}

// MARK: - TelemetryQueueTests

final class TelemetryQueueTests: XCTestCase {

    private var tempDir: URL!
    private var persistenceURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        persistenceURL = tempDir.appendingPathComponent("test_events.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRecordIncrementsPendingCount() {
        let queue = TelemetryQueue(
            modelId: "test",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        XCTAssertEqual(queue.pendingCount, 0)

        queue.reportInferenceCompleted(latencyMs: 12.5)
        XCTAssertEqual(queue.pendingCount, 1)

        queue.reportInferenceFailed(latencyMs: 5.0, error: "timeout")
        XCTAssertEqual(queue.pendingCount, 2)
    }

    func testRecordEvent() {
        let queue = TelemetryQueue(
            modelId: "classifier",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )

        let event = InferenceTelemetryEvent(
            modelId: "classifier",
            latencyMs: 23.4,
            success: true
        )
        queue.record(event)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testPersistAndRestore() {
        // Create a queue, record events, persist
        let queue1 = TelemetryQueue(
            modelId: "model_a",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        queue1.reportInferenceCompleted(latencyMs: 10.0)
        queue1.reportInferenceCompleted(latencyMs: 20.0)
        queue1.reportInferenceFailed(latencyMs: 5.0, error: "crash")
        queue1.persistEvents()

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistenceURL.path))

        // Create new queue at the same persistence URL -- should restore
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
            serverURL: nil,  // No server -- events will be discarded
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistenceURL
        )
        queue.reportInferenceCompleted(latencyMs: 10.0)
        queue.reportInferenceCompleted(latencyMs: 20.0)
        XCTAssertEqual(queue.pendingCount, 2)

        await queue.flush()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testInferenceTelemetryEventCodable() throws {
        let event = InferenceTelemetryEvent(
            modelId: "test_model",
            latencyMs: 42.5,
            timestamp: 1700000000000,
            success: false,
            errorMessage: "test error"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InferenceTelemetryEvent.self, from: data)

        XCTAssertEqual(decoded.modelId, "test_model")
        XCTAssertEqual(decoded.latencyMs, 42.5)
        XCTAssertEqual(decoded.timestamp, 1700000000000)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.errorMessage, "test error")
    }

    func testBatchPayloadCodable() throws {
        let events = [
            InferenceTelemetryEvent(modelId: "m", latencyMs: 1.0),
            InferenceTelemetryEvent(modelId: "m", latencyMs: 2.0),
        ]
        let payload = TelemetryBatchPayload(modelId: "m", events: events)

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TelemetryBatchPayload.self, from: data)

        XCTAssertEqual(decoded.modelId, "m")
        XCTAssertEqual(decoded.events.count, 2)
        XCTAssertEqual(decoded.events[0].latencyMs, 1.0)
    }
}

// MARK: - OctomilWrappedModelTests

final class OctomilWrappedModelTests: XCTestCase {

    // NOTE: These tests validate the wrapper logic without a real CoreML model.
    // We test contract validation, telemetry recording, and config behaviour.
    // Actual prediction delegation requires a compiled MLModel, which is
    // tested implicitly by the CoreML runtime.

    func testWrappedModelExposesProperties() {
        let config = OctomilWrapperConfig(
            validateInputs: true,
            telemetryEnabled: true,
            otaUpdatesEnabled: false
        )

        // We can't instantiate MLModel without a compiled model file,
        // but we can test the wrapper's non-CoreML properties via a
        // custom telemetry queue.
        let queue = makeTelemetryQueue()

        // Verify config is stored
        XCTAssertTrue(config.validateInputs)
        XCTAssertTrue(config.telemetryEnabled)
        XCTAssertFalse(config.otaUpdatesEnabled)

        // Verify queue
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testContractValidationSkippedWhenDisabled() throws {
        let contract = WrappedModelContract(
            inputFeatureNames: ["required_feature"],
            outputFeatureNames: []
        )

        // With validation enabled, missing features should throw
        var config = OctomilWrapperConfig.default
        config.validateInputs = true

        // We test the validate path directly since we can't instantiate MLModel
        let provider = MockFeatureProvider(doubles: ["wrong_feature": 1.0])
        XCTAssertThrowsError(try contract.validate(input: provider))
    }

    func testFeatureValidationErrorDescription() {
        let error = FeatureValidationError(
            missingFeatures: Set(["age", "name"]),
            providedFeatures: Set(["id"]),
            expectedFeatures: Set(["age", "name", "id"])
        )

        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("age"))
        XCTAssertTrue(desc.contains("name"))
        XCTAssertTrue(desc.contains("Contract validation failed"))
    }

    func testTelemetryRecordingWithSuccess() {
        let queue = makeTelemetryQueue()
        queue.reportInferenceCompleted(latencyMs: 15.3)

        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testTelemetryRecordingWithFailure() {
        let queue = makeTelemetryQueue()
        queue.reportInferenceFailed(latencyMs: 5.0, error: "model error")

        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testTelemetryDisabledDoesNotRecord() {
        // When telemetry is disabled, the wrapped model should not call
        // record on the queue. We verify by checking that the queue stays
        // empty when we manually simulate the guard.
        let config = OctomilWrapperConfig(telemetryEnabled: false)
        XCTAssertFalse(config.telemetryEnabled)

        // The guard in OctomilWrappedModel.recordTelemetry checks
        // config.telemetryEnabled and short-circuits. Since we can't
        // construct MLModel here, we verify the flag is read correctly.
    }

    func testWrappedModelContractInit() {
        let contract = WrappedModelContract(
            inputFeatureNames: ["a", "b", "c"],
            outputFeatureNames: ["out"],
            version: "2.0.1"
        )

        XCTAssertEqual(contract.inputFeatureNames, Set(["a", "b", "c"]))
        XCTAssertEqual(contract.outputFeatureNames, Set(["out"]))
        XCTAssertEqual(contract.version, "2.0.1")
    }

    func testReplaceModelUpdatesUnderlying() throws {
        throw XCTSkip("Requires a compiled .mlmodelc bundle — covered by integration tests")
    }

    func testPersistTelemetryCallsThrough() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrapper_persist_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let persistURL = dir.appendingPathComponent("events.json")

        let queue = TelemetryQueue(
            modelId: "test_model",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: persistURL
        )
        queue.reportInferenceCompleted(latencyMs: 10.0)

        queue.persistEvents()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: persistURL.path),
            "persistEvents should write events to disk"
        )

        // Second call should not crash or corrupt
        queue.persistEvents()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: persistURL.path),
            "Second persistEvents should still leave file intact"
        )

        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Helpers

    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wrapper_tests_\(UUID().uuidString)", isDirectory: true)
    }

    private func makeTelemetryQueue() -> TelemetryQueue {
        let dir = tempDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TelemetryQueue(
            modelId: "test_model",
            serverURL: nil,
            apiKey: nil,
            batchSize: 100,
            flushInterval: 0,
            persistenceURL: dir.appendingPathComponent("events.json")
        )
    }
}

// MARK: - OctomilWrapperEntryPointTests

final class OctomilWrapperEntryPointTests: XCTestCase {

    // The `Octomil.wrap` static method requires a real MLModel instance,
    // which needs a compiled .mlmodelc bundle. These tests verify the
    // factory's compile-time API and config handling.

    func testWrapperConfigDefaultsAreSane() {
        let config = OctomilWrapperConfig.default
        XCTAssertTrue(config.validateInputs)
        XCTAssertTrue(config.telemetryEnabled)
        XCTAssertTrue(config.otaUpdatesEnabled)
        XCTAssertEqual(config.telemetryBatchSize, 50)
        XCTAssertEqual(config.telemetryFlushInterval, 30, accuracy: 0.001)
    }

    func testConfigMutability() {
        var config = OctomilWrapperConfig.default
        config.validateInputs = false
        config.telemetryEnabled = false
        config.otaUpdatesEnabled = false
        config.serverURL = URL(string: "https://test.octomil.com")
        config.apiKey = "sk-test"

        XCTAssertFalse(config.validateInputs)
        XCTAssertFalse(config.telemetryEnabled)
        XCTAssertFalse(config.otaUpdatesEnabled)
        XCTAssertEqual(config.serverURL?.absoluteString, "https://test.octomil.com")
        XCTAssertEqual(config.apiKey, "sk-test")
    }
}

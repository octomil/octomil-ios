import XCTest
@testable import Octomil

/// Tests for types introduced in the Android→iOS feature parity port:
/// ``UploadPolicy``, ``TrainingOutcome``, ``MissingTrainingSignatureError``,
/// ``ModelContract``, ``ModelInfo``, ``TensorInfo``, ``WarmupResult``.
final class AndroidPortTypesTests: XCTestCase {

    // MARK: - UploadPolicy

    func testUploadPolicyRawValues() {
        XCTAssertEqual(UploadPolicy.auto.rawValue, "auto")
        XCTAssertEqual(UploadPolicy.manual.rawValue, "manual")
        XCTAssertEqual(UploadPolicy.disabled.rawValue, "disabled")
    }

    func testUploadPolicyCodableRoundTrip() throws {
        for policy in [UploadPolicy.auto, .manual, .disabled] {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(UploadPolicy.self, from: data)
            XCTAssertEqual(decoded, policy)
        }
    }

    func testUploadPolicyDecodingFromString() throws {
        let json = "\"manual\""
        let decoded = try JSONDecoder().decode(UploadPolicy.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded, .manual)
    }

    func testUploadPolicyInvalidRawValueThrows() {
        let json = "\"never\""
        XCTAssertThrowsError(
            try JSONDecoder().decode(UploadPolicy.self, from: json.data(using: .utf8)!)
        )
    }

    // MARK: - TrainingOutcome

    func testTrainingOutcomeDefaults() {
        let result = TrainingResult(
            sampleCount: 100,
            loss: 0.05,
            accuracy: 0.95,
            trainingTime: 10.0,
            metrics: [:]
        )
        let outcome = TrainingOutcome(trainingResult: result)

        XCTAssertNil(outcome.weightUpdate)
        XCTAssertFalse(outcome.uploaded)
        XCTAssertFalse(outcome.secureAggregation)
        XCTAssertEqual(outcome.uploadPolicy, .disabled)
        XCTAssertFalse(outcome.degraded)
        XCTAssertEqual(outcome.trainingResult.sampleCount, 100)
    }

    func testTrainingOutcomeWithAllFields() {
        let result = TrainingResult(
            sampleCount: 500,
            loss: 0.01,
            accuracy: 0.99,
            trainingTime: 30.0,
            metrics: ["f1": 0.98]
        )
        let weights = WeightUpdate(
            modelId: "model-1",
            version: "1.0",
            deviceId: "dev-1",
            weightsData: Data([0x01]),
            sampleCount: 500,
            metrics: ["loss": 0.01]
        )
        let outcome = TrainingOutcome(
            trainingResult: result,
            weightUpdate: weights,
            uploaded: true,
            secureAggregation: true,
            uploadPolicy: .auto,
            degraded: false
        )

        XCTAssertNotNil(outcome.weightUpdate)
        XCTAssertTrue(outcome.uploaded)
        XCTAssertTrue(outcome.secureAggregation)
        XCTAssertEqual(outcome.uploadPolicy, .auto)
        XCTAssertFalse(outcome.degraded)
    }

    func testTrainingOutcomeDegradedMode() {
        let result = TrainingResult(
            sampleCount: 50,
            loss: nil,
            accuracy: nil,
            trainingTime: 1.0,
            metrics: ["degraded": 1.0]
        )
        let outcome = TrainingOutcome(
            trainingResult: result,
            degraded: true
        )

        XCTAssertTrue(outcome.degraded)
        XCTAssertNil(outcome.trainingResult.loss)
        XCTAssertNil(outcome.trainingResult.accuracy)
    }

    // MARK: - MissingTrainingSignatureError

    func testMissingTrainingSignatureErrorDescription() {
        let error = MissingTrainingSignatureError(availableSignatures: ["infer", "predict"])
        let desc = error.errorDescription!

        XCTAssertTrue(desc.contains("does not support on-device training"))
        XCTAssertTrue(desc.contains("infer"))
        XCTAssertTrue(desc.contains("predict"))
        XCTAssertTrue(desc.contains("allowDegradedTraining"))
    }

    func testMissingTrainingSignatureErrorEmptySignatures() {
        let error = MissingTrainingSignatureError(availableSignatures: [])
        XCTAssertTrue(error.availableSignatures.isEmpty)
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - ModelContract

    func testModelContractInputSize() {
        let contract = ModelContract(
            modelId: "mnist",
            version: "1.0",
            inputShape: [1, 28, 28, 1],
            outputShape: [1, 10],
            inputType: "FLOAT32",
            outputType: "FLOAT32",
            hasTrainingSignature: true,
            signatureKeys: ["train", "infer"]
        )

        XCTAssertEqual(contract.inputSize, 784) // 1 * 28 * 28 * 1
        XCTAssertEqual(contract.outputSize, 10) // 1 * 10
    }

    func testModelContractValidateInput() {
        let contract = ModelContract(
            modelId: "test",
            version: "1.0",
            inputShape: [1, 4],
            outputShape: [1, 2],
            inputType: "FLOAT32",
            outputType: "FLOAT32",
            hasTrainingSignature: false,
            signatureKeys: ["infer"]
        )

        let validInput = [Float](repeating: 0, count: 4)
        let invalidInput = [Float](repeating: 0, count: 5)

        XCTAssertTrue(contract.validateInput(validInput))
        XCTAssertFalse(contract.validateInput(invalidInput))
    }

    func testModelContractRequireValidInput() {
        let contract = ModelContract(
            modelId: "test",
            version: "1.0",
            inputShape: [1, 3],
            outputShape: [1, 1],
            inputType: "FLOAT32",
            outputType: "FLOAT32",
            hasTrainingSignature: false,
            signatureKeys: ["infer"]
        )

        let valid = [Float](repeating: 0, count: 3)
        XCTAssertNoThrow(try contract.requireValidInput(valid))

        let invalid = [Float](repeating: 0, count: 10)
        XCTAssertThrowsError(try contract.requireValidInput(invalid)) { error in
            XCTAssertTrue(error is ModelContractValidationError)
            let validationError = error as! ModelContractValidationError
            XCTAssertEqual(validationError.actual, 10)
            XCTAssertEqual(validationError.expected, 3)
        }
    }

    func testModelContractInputDescription() {
        let contract = ModelContract(
            modelId: "test",
            version: "1.0",
            inputShape: [1, 28, 28, 1],
            outputShape: [1, 10],
            inputType: "FLOAT32",
            outputType: "FLOAT32",
            hasTrainingSignature: true,
            signatureKeys: ["train", "infer"]
        )

        let desc = contract.inputDescription
        XCTAssertTrue(desc.contains("784"))
        XCTAssertTrue(desc.contains("FLOAT32"))
        XCTAssertTrue(desc.contains("[1, 28, 28, 1]"))
    }

    func testModelContractSignatureKeys() {
        let updatable = ModelContract(
            modelId: "m1", version: "1.0",
            inputShape: [], outputShape: [],
            inputType: "FLOAT32", outputType: "FLOAT32",
            hasTrainingSignature: true,
            signatureKeys: ["train", "infer"]
        )
        XCTAssertTrue(updatable.hasTrainingSignature)
        XCTAssertEqual(updatable.signatureKeys, ["train", "infer"])

        let inferOnly = ModelContract(
            modelId: "m2", version: "1.0",
            inputShape: [], outputShape: [],
            inputType: "FLOAT32", outputType: "FLOAT32",
            hasTrainingSignature: false,
            signatureKeys: ["infer"]
        )
        XCTAssertFalse(inferOnly.hasTrainingSignature)
        XCTAssertEqual(inferOnly.signatureKeys, ["infer"])
    }

    // MARK: - ModelContractValidationError

    func testModelContractValidationErrorDescription() {
        let error = ModelContractValidationError(
            actual: 100,
            expected: 784,
            inputDescription: "[Float][784] shape=[1, 28, 28, 1] type=FLOAT32"
        )

        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("100"))
        XCTAssertTrue(desc.contains("784"))
    }

    // MARK: - TensorInfo

    func testTensorInfoProperties() {
        let info = TensorInfo(
            inputShape: [1, 224, 224, 3],
            outputShape: [1, 1000],
            inputType: "Image",
            outputType: "MultiArray"
        )

        XCTAssertEqual(info.inputShape, [1, 224, 224, 3])
        XCTAssertEqual(info.outputShape, [1, 1000])
        XCTAssertEqual(info.inputType, "Image")
        XCTAssertEqual(info.outputType, "MultiArray")
    }

    // MARK: - ModelInfo

    func testModelInfoProperties() {
        let info = ModelInfo(
            modelId: "resnet50",
            version: "2.0.0",
            format: .coreml,
            sizeBytes: 104857600,
            inputShape: [1, 224, 224, 3],
            outputShape: [1, 1000],
            usingNeuralEngine: true
        )

        XCTAssertEqual(info.modelId, "resnet50")
        XCTAssertEqual(info.version, "2.0.0")
        XCTAssertEqual(info.format, .coreml)
        XCTAssertEqual(info.sizeBytes, 104857600)
        XCTAssertEqual(info.inputShape, [1, 224, 224, 3])
        XCTAssertEqual(info.outputShape, [1, 1000])
        XCTAssertTrue(info.usingNeuralEngine)
    }

    // MARK: - WarmupResult

    func testWarmupResultProperties() {
        let result = WarmupResult(
            coldInferenceMs: 150.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: 8.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: []
        )

        XCTAssertEqual(result.coldInferenceMs, 150.0)
        XCTAssertEqual(result.warmInferenceMs, 5.0)
        XCTAssertEqual(result.cpuInferenceMs, 8.0)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "neural_engine")
        XCTAssertFalse(result.delegateDisabled)
    }

    func testWarmupResultDelegateDisabled() {
        let result = WarmupResult(
            coldInferenceMs: 200.0,
            warmInferenceMs: 12.0,
            cpuInferenceMs: 8.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine"]
        )

        XCTAssertFalse(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "cpu")
        XCTAssertTrue(result.delegateDisabled)
        XCTAssertEqual(result.disabledDelegates, ["neural_engine"])
    }

    func testWarmupResultNoCpuBenchmark() {
        let result = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 3.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu"
        )

        XCTAssertNil(result.cpuInferenceMs)
        XCTAssertFalse(result.delegateDisabled)
        XCTAssertTrue(result.disabledDelegates.isEmpty)
    }
}

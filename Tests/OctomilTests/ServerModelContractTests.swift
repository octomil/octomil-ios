import XCTest
@testable import Octomil

final class ServerModelContractTests: XCTestCase {

    // MARK: - ServerTensorSpec JSON Decoding

    func testServerTensorSpecDecodingWithStaticShape() throws {
        let json = """
        {
            "name": "input_0",
            "dtype": "float32",
            "shape": [1, 28, 28, 1],
            "description": "MNIST grayscale image"
        }
        """

        let spec = try JSONDecoder().decode(ServerTensorSpec.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(spec.name, "input_0")
        XCTAssertEqual(spec.dtype, "float32")
        XCTAssertEqual(spec.shape, [1, 28, 28, 1])
        XCTAssertEqual(spec.description, "MNIST grayscale image")
    }

    func testServerTensorSpecDecodingWithDynamicDimension() throws {
        let json = """
        {
            "name": "input_0",
            "dtype": "float32",
            "shape": [null, 224, 224, 3],
            "description": null
        }
        """

        let spec = try JSONDecoder().decode(ServerTensorSpec.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(spec.name, "input_0")
        XCTAssertEqual(spec.dtype, "float32")
        XCTAssertEqual(spec.shape.count, 4)
        XCTAssertNil(spec.shape[0])
        XCTAssertEqual(spec.shape[1], 224)
        XCTAssertEqual(spec.shape[2], 224)
        XCTAssertEqual(spec.shape[3], 3)
        XCTAssertNil(spec.description)
    }

    func testServerTensorSpecDecodingMultipleDynamicDimensions() throws {
        let json = """
        {
            "name": "input_0",
            "dtype": "float32",
            "shape": [null, null, 3]
        }
        """

        let spec = try JSONDecoder().decode(ServerTensorSpec.self, from: json.data(using: .utf8)!)

        XCTAssertNil(spec.shape[0])
        XCTAssertNil(spec.shape[1])
        XCTAssertEqual(spec.shape[2], 3)
    }

    func testServerTensorSpecFixedElementCountAllStatic() {
        let spec = ServerTensorSpec(name: "input_0", dtype: "float32", shape: [1, 28, 28, 1])
        XCTAssertEqual(spec.fixedElementCount, 784) // 1 * 28 * 28 * 1
    }

    func testServerTensorSpecFixedElementCountWithDynamic() {
        let spec = ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 224, 224, 3])
        XCTAssertEqual(spec.fixedElementCount, 150528) // 224 * 224 * 3
    }

    func testServerTensorSpecFixedElementCountEmptyShape() {
        let spec = ServerTensorSpec(name: "input_0", dtype: "float32", shape: [])
        XCTAssertNil(spec.fixedElementCount)
    }

    func testServerTensorSpecFixedElementCountAllDynamic() {
        let spec = ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, nil])
        // compactMap removes nils, reduce of empty = 1
        XCTAssertEqual(spec.fixedElementCount, 1)
    }

    // MARK: - ServerModelContract JSON Decoding

    func testServerModelContractDecoding() throws {
        let json = """
        {
            "inputs": [
                {"name": "input_0", "dtype": "float32", "shape": [null, 224, 224, 3], "description": null}
            ],
            "outputs": [
                {"name": "output_0", "dtype": "float32", "shape": [null, 1000], "description": null}
            ]
        }
        """

        let contract = try JSONDecoder().decode(ServerModelContract.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(contract.inputs.count, 1)
        XCTAssertEqual(contract.outputs.count, 1)
        XCTAssertEqual(contract.inputs[0].name, "input_0")
        XCTAssertEqual(contract.inputs[0].dtype, "float32")
        XCTAssertEqual(contract.inputs[0].shape, [nil, 224, 224, 3])
        XCTAssertEqual(contract.outputs[0].name, "output_0")
        XCTAssertEqual(contract.outputs[0].shape, [nil, 1000])
    }

    func testServerModelContractDecodingMultipleInputs() throws {
        let json = """
        {
            "inputs": [
                {"name": "image", "dtype": "float32", "shape": [1, 3, 224, 224]},
                {"name": "mask", "dtype": "int64", "shape": [1, 224, 224]}
            ],
            "outputs": [
                {"name": "logits", "dtype": "float32", "shape": [1, 21, 224, 224]}
            ]
        }
        """

        let contract = try JSONDecoder().decode(ServerModelContract.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(contract.inputs.count, 2)
        XCTAssertEqual(contract.inputs[0].name, "image")
        XCTAssertEqual(contract.inputs[1].name, "mask")
        XCTAssertEqual(contract.outputs.count, 1)
    }

    func testServerModelContractRoundTrip() throws {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 28, 28, 1])],
            outputs: [ServerTensorSpec(name: "output_0", dtype: "float32", shape: [nil, 10])]
        )

        let data = try JSONEncoder().encode(contract)
        let decoded = try JSONDecoder().decode(ServerModelContract.self, from: data)

        XCTAssertEqual(decoded, contract)
    }

    // MARK: - Input Validation: Static Shape

    func testValidateInputCorrectSizeStaticShape() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [1, 28, 28, 1])],
            outputs: []
        )

        let input = [Float](repeating: 0.0, count: 784) // 1 * 28 * 28 * 1
        let result = contract.validateInput(input)

        switch result {
        case .success:
            break // expected
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error.localizedDescription ?? "unknown")")
        }
    }

    func testValidateInputWrongSizeStaticShape() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [1, 28, 28, 1])],
            outputs: []
        )

        let input = [Float](repeating: 0.0, count: 100) // wrong size
        let result = contract.validateInput(input)

        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error.tensorName, "input_0")
            XCTAssertEqual(error.expectedFixedCount, 784)
            XCTAssertEqual(error.actualCount, 100)
            XCTAssertFalse(error.hasDynamicDimensions)
            XCTAssertNotNil(error.errorDescription)
            XCTAssertTrue(error.errorDescription!.contains("784"))
            XCTAssertTrue(error.errorDescription!.contains("100"))
            XCTAssertTrue(error.errorDescription!.contains("input_0"))
        }
    }

    // MARK: - Input Validation: Dynamic Dimensions

    func testValidateInputCorrectSizeDynamicBatch() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 224, 224, 3])],
            outputs: []
        )

        // Single image: 1 * 224 * 224 * 3 = 150528
        let input = [Float](repeating: 0.0, count: 150528)
        let result = contract.validateInput(input)

        switch result {
        case .success:
            break // expected
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error.localizedDescription ?? "unknown")")
        }
    }

    func testValidateInputBatchOfTwoDynamicBatch() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 224, 224, 3])],
            outputs: []
        )

        // Batch of 2: 2 * 224 * 224 * 3 = 301056
        let input = [Float](repeating: 0.0, count: 301056)
        let result = contract.validateInput(input)

        switch result {
        case .success:
            break // expected
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error.localizedDescription ?? "unknown")")
        }
    }

    func testValidateInputWrongSizeDynamicBatch() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 224, 224, 3])],
            outputs: []
        )

        // Not a multiple of 150528
        let input = [Float](repeating: 0.0, count: 150529)
        let result = contract.validateInput(input)

        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error.tensorName, "input_0")
            XCTAssertTrue(error.hasDynamicDimensions)
            XCTAssertEqual(error.expectedFixedCount, 150528)
            XCTAssertEqual(error.actualCount, 150529)
            XCTAssertTrue(error.errorDescription!.contains("not a multiple"))
        }
    }

    func testValidateInputZeroCountDynamicBatch() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 10])],
            outputs: []
        )

        let input: [Float] = []
        let result = contract.validateInput(input)

        switch result {
        case .success:
            XCTFail("Expected failure for empty input")
        case .failure(let error):
            XCTAssertTrue(error.hasDynamicDimensions)
            XCTAssertEqual(error.actualCount, 0)
        }
    }

    // MARK: - Input Validation: No Contract / Empty Inputs

    func testValidateInputNoInputSpecs() {
        let contract = ServerModelContract(inputs: [], outputs: [])

        let input = [Float](repeating: 0.0, count: 42)
        let result = contract.validateInput(input)

        switch result {
        case .success:
            break // expected — no input spec means nothing to validate
        case .failure:
            XCTFail("Expected success when no input specs are defined")
        }
    }

    func testValidateInputAllDynamicDimensions() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, nil])],
            outputs: []
        )

        let input = [Float](repeating: 0.0, count: 42)
        let result = contract.validateInput(input)

        switch result {
        case .success:
            break // expected — all dimensions are dynamic, can't validate
        case .failure:
            XCTFail("Expected success when all dimensions are dynamic")
        }
    }

    func testValidateInputEmptyShape() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [])],
            outputs: []
        )

        let input = [Float](repeating: 0.0, count: 5)
        let result = contract.validateInput(input)

        switch result {
        case .success:
            break // expected — empty shape, nothing to validate
        case .failure:
            XCTFail("Expected success when shape is empty")
        }
    }

    // MARK: - ContractValidationError Messages

    func testContractValidationErrorStaticMessage() {
        let error = ContractValidationError(
            tensorName: "input_0",
            expectedShape: [1, 28, 28, 1],
            expectedFixedCount: 784,
            actualCount: 100,
            hasDynamicDimensions: false
        )

        let message = error.errorDescription!
        XCTAssertTrue(message.contains("input_0"))
        XCTAssertTrue(message.contains("784"))
        XCTAssertTrue(message.contains("100"))
        XCTAssertTrue(message.contains("1, 28, 28, 1"))
    }

    func testContractValidationErrorDynamicMessage() {
        let error = ContractValidationError(
            tensorName: "features",
            expectedShape: [nil, 224, 224, 3],
            expectedFixedCount: 150528,
            actualCount: 999,
            hasDynamicDimensions: true
        )

        let message = error.errorDescription!
        XCTAssertTrue(message.contains("features"))
        XCTAssertTrue(message.contains("not a multiple"))
        XCTAssertTrue(message.contains("150528"))
        XCTAssertTrue(message.contains("999"))
        XCTAssertTrue(message.contains("?, 224, 224, 3"))
    }

    // MARK: - ModelVersionResponse with Contract

    func testModelVersionResponseWithContractDecoding() throws {
        let json = """
        {
            "model_id": "image-classifier",
            "version": "2.0.0",
            "checksum": "sha256:abc123",
            "size_bytes": 52428800,
            "format": "coreml",
            "description": "Image classifier",
            "created_at": "2026-02-01T00:00:00Z",
            "metrics": null,
            "model_contract": {
                "inputs": [
                    {"name": "input_0", "dtype": "float32", "shape": [null, 224, 224, 3], "description": null}
                ],
                "outputs": [
                    {"name": "output_0", "dtype": "float32", "shape": [null, 1000], "description": null}
                ]
            }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ModelVersionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertNotNil(response.modelContract)
        XCTAssertEqual(response.modelContract?.inputs.count, 1)
        XCTAssertEqual(response.modelContract?.inputs[0].name, "input_0")
        XCTAssertEqual(response.modelContract?.inputs[0].shape, [nil, 224, 224, 3])
        XCTAssertEqual(response.modelContract?.outputs[0].shape, [nil, 1000])
    }

    func testModelVersionResponseWithoutContractDecoding() throws {
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

        XCTAssertNil(response.modelContract)
    }

    func testModelVersionResponseNullContractDecoding() throws {
        let json = """
        {
            "model_id": "basic",
            "version": "1.0.0",
            "checksum": "abc",
            "size_bytes": 1024,
            "format": "onnx",
            "description": null,
            "created_at": "2026-01-01T00:00:00Z",
            "metrics": null,
            "model_contract": null
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ModelVersionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertNil(response.modelContract)
    }

    // MARK: - ModelMetadata with ServerContract

    func testModelMetadataWithServerContract() {
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [1, 10])],
            outputs: [ServerTensorSpec(name: "output_0", dtype: "float32", shape: [1, 5])]
        )

        let metadata = ModelMetadata(
            modelId: "test-model",
            version: "1.0.0",
            checksum: "abc",
            fileSize: 1024,
            createdAt: Date(),
            format: "coreml",
            supportsTraining: false,
            description: nil,
            inputSchema: nil,
            outputSchema: nil,
            serverContract: contract
        )

        XCTAssertNotNil(metadata.serverContract)
        XCTAssertEqual(metadata.serverContract?.inputs[0].shape, [1, 10])
    }

    func testModelMetadataWithoutServerContract() {
        let metadata = ModelMetadata(
            modelId: "test-model",
            version: "1.0.0",
            checksum: "abc",
            fileSize: 1024,
            createdAt: Date(),
            format: "coreml",
            supportsTraining: false,
            description: nil,
            inputSchema: nil,
            outputSchema: nil
        )

        XCTAssertNil(metadata.serverContract)
    }

    // MARK: - Edge Cases

    func testValidateInputScalarShape() {
        // Shape [1] => expects 1 element
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "scalar", dtype: "float32", shape: [1])],
            outputs: []
        )

        let validResult = contract.validateInput([1.0])
        if case .failure(let err) = validResult {
            XCTFail("Expected success, got failure: \(err)")
        }

        let invalidResult = contract.validateInput([1.0, 2.0])
        if case .failure(let error) = invalidResult {
            XCTAssertEqual(error.expectedFixedCount, 1)
            XCTAssertEqual(error.actualCount, 2)
        } else {
            XCTFail("Expected failure for wrong size")
        }
    }

    func testValidateInputLargeShape() {
        // Typical image model: [1, 3, 512, 512]
        let contract = ServerModelContract(
            inputs: [ServerTensorSpec(name: "image", dtype: "float32", shape: [1, 3, 512, 512])],
            outputs: []
        )

        let expectedCount = 1 * 3 * 512 * 512 // 786432
        let validInput = [Float](repeating: 0.0, count: expectedCount)
        let result = contract.validateInput(validInput)

        switch result {
        case .success:
            break // expected
        case .failure:
            XCTFail("Expected success for correctly sized large input")
        }
    }

    func testServerTensorSpecEquatable() {
        let spec1 = ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 10])
        let spec2 = ServerTensorSpec(name: "input_0", dtype: "float32", shape: [nil, 10])
        let spec3 = ServerTensorSpec(name: "input_1", dtype: "float32", shape: [nil, 10])

        XCTAssertEqual(spec1, spec2)
        XCTAssertNotEqual(spec1, spec3)
    }

    func testServerModelContractEquatable() {
        let contract1 = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [1, 10])],
            outputs: [ServerTensorSpec(name: "output_0", dtype: "float32", shape: [1, 5])]
        )
        let contract2 = ServerModelContract(
            inputs: [ServerTensorSpec(name: "input_0", dtype: "float32", shape: [1, 10])],
            outputs: [ServerTensorSpec(name: "output_0", dtype: "float32", shape: [1, 5])]
        )

        XCTAssertEqual(contract1, contract2)
    }

    func testContractValidationErrorEquatable() {
        let error1 = ContractValidationError(
            tensorName: "input_0",
            expectedShape: [1, 10],
            expectedFixedCount: 10,
            actualCount: 5,
            hasDynamicDimensions: false
        )
        let error2 = ContractValidationError(
            tensorName: "input_0",
            expectedShape: [1, 10],
            expectedFixedCount: 10,
            actualCount: 5,
            hasDynamicDimensions: false
        )

        XCTAssertEqual(error1, error2)
    }

    // MARK: - MNIST Example (Full Integration)

    func testMNISTContractValidation() throws {
        // Simulate the server returning a contract for an MNIST model
        let json = """
        {
            "inputs": [
                {"name": "image", "dtype": "float32", "shape": [1, 28, 28, 1], "description": "Grayscale 28x28 image"}
            ],
            "outputs": [
                {"name": "probabilities", "dtype": "float32", "shape": [1, 10], "description": "10-class softmax"}
            ]
        }
        """

        let contract = try JSONDecoder().decode(ServerModelContract.self, from: json.data(using: .utf8)!)

        // Valid MNIST input: 1 * 28 * 28 * 1 = 784 elements
        let validInput = [Float](repeating: 0.5, count: 784)
        let validResult = contract.validateInput(validInput)
        if case .failure(let err) = validResult {
            XCTFail("Expected success, got failure: \(err)")
        }

        // Wrong size: user accidentally passed raw image bytes (28 * 28 = 784, but wrong channel count)
        let wrongInput = [Float](repeating: 0.5, count: 28 * 28 * 3) // RGB instead of grayscale
        let wrongResult = contract.validateInput(wrongInput)
        if case .failure(let error) = wrongResult {
            XCTAssertEqual(error.expectedFixedCount, 784)
            XCTAssertEqual(error.actualCount, 2352)
        } else {
            XCTFail("Expected failure for wrong channel count")
        }
    }
}


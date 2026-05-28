import Foundation

// MARK: - Tensor Info

/// Information about a model's input and output tensors.
public struct TensorInfo: Sendable {
    /// Expected input tensor shape (e.g., [1, 28, 28, 1] for MNIST).
    public let inputShape: [Int]

    /// Expected output tensor shape (e.g., [1, 10] for 10-class classifier).
    public let outputShape: [Int]

    /// Input tensor data type (e.g., "FLOAT32", "MultiArray").
    public let inputType: String

    /// Output tensor data type (e.g., "FLOAT32", "MultiArray").
    public let outputType: String

    public init(inputShape: [Int], outputShape: [Int], inputType: String, outputType: String) {
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.inputType = inputType
        self.outputType = outputType
    }
}

// MARK: - Model Info

/// Summary information about a loaded model.
public struct ModelInfo: Sendable {
    /// Model identifier.
    public let modelId: String

    /// Model version.
    public let version: String

    /// Model artifact format (e.g., `.coreml`, `.tflite`). `nil` for
    /// locally-created placeholders whose format is resolved server-side.
    public let format: ArtifactFormat?

    /// Model file size in bytes.
    public let sizeBytes: Int64

    /// Expected input tensor shape.
    public let inputShape: [Int]

    /// Expected output tensor shape.
    public let outputShape: [Int]

    /// Whether the model is using the Neural Engine.
    public let usingNeuralEngine: Bool

    public init(
        modelId: String,
        version: String,
        format: ArtifactFormat?,
        sizeBytes: Int64,
        inputShape: [Int],
        outputShape: [Int],
        usingNeuralEngine: Bool
    ) {
        self.modelId = modelId
        self.version = version
        self.format = format
        self.sizeBytes = sizeBytes
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.usingNeuralEngine = usingNeuralEngine
    }
}

// MARK: - Model Contract

/// Describes the input/output contract of a loaded model.
///
/// Use this at initialization time to validate that your data pipeline
/// produces tensors with the correct shape and type. This catches
/// mismatches early rather than at inference time.
///
/// ```swift
/// let contract = client.getModelContract()!
///
/// // Check input compatibility
/// let myInput = [Float](repeating: 0, count: 784)
/// guard contract.validateInput(myInput) else {
///     fatalError("Bad input: \(contract.inputDescription)")
/// }
///
/// // Check training support
/// if !contract.hasTrainingSignature {
///     print("Model does not support on-device training")
/// }
/// ```
public struct ModelContract: Sendable {
    /// Model identifier.
    public let modelId: String

    /// Model version.
    public let version: String

    /// Input/output tensor specification.
    public let tensorSpec: TensorSpec

    /// Whether the model supports on-device gradient-based training.
    public let hasTrainingSignature: Bool

    /// Available signature or capability keys (e.g., ["train", "infer", "save"]).
    public let signatureKeys: [String]

    /// Describes the shape and data type of a model's input and output tensors.
    public struct TensorSpec: Sendable {
        /// Expected input tensor shape (e.g., [1, 28, 28, 1] for MNIST).
        public let inputShape: [Int]
        /// Expected output tensor shape (e.g., [1, 10] for 10-class classifier).
        public let outputShape: [Int]
        /// Input tensor data type (e.g., "FLOAT32", "MultiArray").
        public let inputType: String
        /// Output tensor data type (e.g., "FLOAT32", "MultiArray").
        public let outputType: String

        public init(inputShape: [Int], outputShape: [Int], inputType: String, outputType: String) {
            self.inputShape = inputShape
            self.outputShape = outputShape
            self.inputType = inputType
            self.outputType = outputType
        }
    }

    /// Shorthand accessors for tensor spec fields.
    public var inputShape: [Int] { tensorSpec.inputShape }
    public var outputShape: [Int] { tensorSpec.outputShape }
    public var inputType: String { tensorSpec.inputType }
    public var outputType: String { tensorSpec.outputType }

    public init(
        modelId: String,
        version: String,
        tensorSpec: TensorSpec,
        hasTrainingSignature: Bool,
        signatureKeys: [String]
    ) {
        self.modelId = modelId
        self.version = version
        self.tensorSpec = tensorSpec
        self.hasTrainingSignature = hasTrainingSignature
        self.signatureKeys = signatureKeys
    }

    /// Convenience initializer maintaining the original 8-parameter signature.
    public init(
        modelId: String,
        version: String,
        inputShape: [Int],
        outputShape: [Int],
        inputType: String,
        outputType: String,
        hasTrainingSignature: Bool,
        signatureKeys: [String]
    ) {
        self.init(
            modelId: modelId,
            version: version,
            tensorSpec: TensorSpec(inputShape: inputShape, outputShape: outputShape, inputType: inputType, outputType: outputType),
            hasTrainingSignature: hasTrainingSignature,
            signatureKeys: signatureKeys
        )
    }

    /// Total number of input elements expected (product of input shape dimensions).
    public var inputSize: Int {
        inputShape.reduce(1, *)
    }

    /// Total number of output elements produced (product of output shape dimensions).
    public var outputSize: Int {
        outputShape.reduce(1, *)
    }

    /// Human-readable description of expected input
    /// (e.g., "[Float][784] shape=[1, 28, 28, 1] type=FLOAT32").
    public var inputDescription: String {
        "[Float][\(inputSize)] shape=\(inputShape) type=\(inputType)"
    }

    /// Human-readable description of output
    /// (e.g., "[Float][10] shape=[1, 10] type=FLOAT32").
    public var outputDescription: String {
        "[Float][\(outputSize)] shape=\(outputShape) type=\(outputType)"
    }

    /// Validate that a float array is compatible with this model's input.
    ///
    /// - Parameter input: The data to validate.
    /// - Returns: `true` if the input count matches the model's expected input size.
    public func validateInput(_ input: [Float]) -> Bool {
        input.count == inputSize
    }

    /// Validate that a float array is compatible with this model's input,
    /// throwing a descriptive error if not.
    ///
    /// - Parameter input: The data to validate.
    /// - Throws: An error if the input size doesn't match.
    public func requireValidInput(_ input: [Float]) throws {
        guard input.count == inputSize else {
            throw ModelContractValidationError(
                actual: input.count,
                expected: inputSize,
                inputDescription: inputDescription
            )
        }
    }
}

/// Error thrown when model input validation fails.
public struct ModelContractValidationError: LocalizedError, Sendable {
    public let actual: Int
    public let expected: Int
    public let inputDescription: String

    public var errorDescription: String? {
        "Input size mismatch: got \(actual) elements, expected \(inputDescription)"
    }
}

// MARK: - Server Model Contract

/// Specification of a single tensor from the server's model contract.
///
/// Matches the server JSON format:
/// ```json
/// {"name": "input_0", "dtype": "float32", "shape": [null, 224, 224, 3], "description": null}
/// ```
/// A `nil` value in `shape` represents a dynamic dimension (e.g., batch size).
public struct ServerTensorSpec: Codable, Sendable, Equatable {
    /// Tensor name (e.g., "input_0").
    public let name: String

    /// Data type string (e.g., "float32", "int64").
    public let dtype: String

    /// Tensor shape. `nil` entries represent dynamic dimensions (e.g., batch size).
    public let shape: [Int?]

    /// Optional human-readable description of this tensor.
    public let description: String?

    public init(name: String, dtype: String, shape: [Int?], description: String? = nil) {
        self.name = name
        self.dtype = dtype
        self.shape = shape
        self.description = description
    }

    /// The product of all non-nil (fixed) dimensions in the shape.
    ///
    /// For a shape like `[nil, 224, 224, 3]`, this returns `224 * 224 * 3 = 150528`.
    /// Returns `nil` if the shape is empty.
    public var fixedElementCount: Int? {
        guard !shape.isEmpty else { return nil }
        return shape.compactMap { $0 }.reduce(1, *)
    }
}

/// A model contract as returned by the server, describing expected input/output tensor specifications.
///
/// Use this to validate inference inputs before calling CoreML, catching shape mismatches
/// early with descriptive error messages.
///
/// ```swift
/// if let contract = model.serverContract {
///     let result = contract.validateInput(myFloatArray)
///     if case .failure(let error) = result {
///         print("Bad input: \(error.localizedDescription)")
///     }
/// }
/// ```
public struct ServerModelContract: Codable, Sendable, Equatable {
    /// Expected input tensor specifications.
    public let inputs: [ServerTensorSpec]

    /// Expected output tensor specifications.
    public let outputs: [ServerTensorSpec]

    public init(inputs: [ServerTensorSpec], outputs: [ServerTensorSpec]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    /// Validates that a float array's element count is compatible with the first input tensor's shape.
    ///
    /// - Dynamic (`nil`) dimensions in the shape are excluded from the size calculation.
    /// - If no inputs are defined, validation passes (nothing to check).
    /// - Only the first input tensor is checked (single-input models).
    ///
    /// - Parameter input: The float array to validate.
    /// - Returns: `.success` if compatible, `.failure` with a descriptive error otherwise.
    public func validateInput(_ input: [Float]) -> Result<Void, ContractValidationError> {
        guard let firstInput = inputs.first else {
            // No input spec defined — nothing to validate against.
            return .success(())
        }

        guard let expectedCount = firstInput.fixedElementCount, expectedCount > 0 else {
            // All dimensions are dynamic or shape is empty — cannot validate.
            return .success(())
        }

        let hasDynamic = firstInput.shape.contains(where: { $0 == nil })

        if hasDynamic {
            // With dynamic dimensions, the input count must be an exact multiple
            // of the fixed element count (the dynamic dims act as a batch axis).
            guard input.count > 0, input.count.isMultiple(of: expectedCount) else {
                return .failure(ContractValidationError(
                    tensorName: firstInput.name,
                    expectedShape: firstInput.shape,
                    expectedFixedCount: expectedCount,
                    actualCount: input.count,
                    hasDynamicDimensions: true
                ))
            }
        } else {
            // Fully static shape — exact match required.
            guard input.count == expectedCount else {
                return .failure(ContractValidationError(
                    tensorName: firstInput.name,
                    expectedShape: firstInput.shape,
                    expectedFixedCount: expectedCount,
                    actualCount: input.count,
                    hasDynamicDimensions: false
                ))
            }
        }

        return .success(())
    }
}

/// Error describing a mismatch between an input array and a server model contract.
public struct ContractValidationError: LocalizedError, Sendable, Equatable {
    /// Name of the tensor that failed validation.
    public let tensorName: String

    /// Expected tensor shape (with `nil` for dynamic dimensions).
    public let expectedShape: [Int?]

    /// Product of fixed (non-nil) dimensions.
    public let expectedFixedCount: Int

    /// Actual element count provided.
    public let actualCount: Int

    /// Whether the shape contains dynamic dimensions.
    public let hasDynamicDimensions: Bool

    public var errorDescription: String? {
        let shapeStr = expectedShape.map { $0.map(String.init) ?? "?" }.joined(separator: ", ")
        if hasDynamicDimensions {
            return "Contract violation for '\(tensorName)': " +
                "input has \(actualCount) elements which is not a multiple of " +
                "the fixed dimensions product \(expectedFixedCount) " +
                "(shape: [\(shapeStr)])"
        } else {
            return "Contract violation for '\(tensorName)': " +
                "expected \(expectedFixedCount) elements (shape: [\(shapeStr)]), " +
                "got \(actualCount)"
        }
    }
}

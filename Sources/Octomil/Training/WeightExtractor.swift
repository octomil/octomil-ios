import Foundation
import CoreML
import os.log

/// Utility for extracting and serializing model weights from CoreML models.
///
/// CoreML doesn't provide direct access to model weights, so this implementation
/// uses the MLModel inspection APIs to extract parameters and compute deltas.
actor WeightExtractor {

    private let logger: Logger

    init() {
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "WeightExtractor")
    }

    // MARK: - Weight Extraction

    /// Extracts weight deltas from a trained model by comparing with the original.
    ///
    /// - Parameters:
    ///   - originalModelURL: URL to the original (pre-training) model.
    ///   - updatedContext: MLUpdateContext containing the trained model.
    /// - Returns: Serialized weight delta in PyTorch-compatible format.
    /// - Throws: OctomilError if extraction fails.
    func extractWeightDelta(
        originalModelURL: URL,
        updatedContext: MLUpdateContext
    ) async throws -> Data {
        logger.info("Extracting weight delta from trained model")

        // Write updated model to temporary location
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mlmodelc")

        try updatedContext.model.write(to: tempURL)

        defer {
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Extract weights from both models
        let originalWeights = try await extractWeights(from: originalModelURL)
        let updatedWeights = try await extractWeights(from: tempURL)

        // Compute delta (updated - original)
        let delta = computeDelta(original: originalWeights, updated: updatedWeights)

        // Serialize to PyTorch format
        let serialized = try serializeToPyTorch(delta: delta)

        logger.info("Weight delta extracted: \(serialized.count) bytes")

        return serialized
    }

    /// Extracts full weights from a trained model (for full weight uploads).
    ///
    /// - Parameter updatedContext: MLUpdateContext containing the trained model.
    /// - Returns: Serialized full weights in PyTorch-compatible format.
    /// - Throws: OctomilError if extraction fails.
    func extractFullWeights(
        updatedContext: MLUpdateContext
    ) async throws -> Data {
        logger.info("Extracting full weights from trained model")

        // Write updated model to temporary location
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mlmodelc")

        try updatedContext.model.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Extract weights
        let weights = try await extractWeights(from: tempURL)

        // Serialize to PyTorch format
        let serialized = try serializeToPyTorch(delta: weights)

        logger.info("Full weights extracted: \(serialized.count) bytes")

        return serialized
    }

    // MARK: - Private Methods

    /// Extracts weights from a CoreML model using the model's parameter structure.
    ///
    /// Uses `MLModelDescription.trainingInputDescriptionsByName` and
    /// `MLModel.parameterValue(for:)` on iOS 16+ to access updatable layer weights.
    /// Falls back to training input inspection on older systems.
    private func extractWeights(from modelURL: URL) async throws -> [String: MLMultiArray] {
        var weights: [String: MLMultiArray] = [:]

        do {
            let model = try MLModel(contentsOf: modelURL)
            let description = model.modelDescription

            // Get the updatable parameter keys from the model description.
            // Updatable models expose their trainable layers through
            // trainingInputDescriptionsByName (available on all updatable models).
            let parameterKeys = extractParameterKeys(from: description)

            if parameterKeys.isEmpty {
                logger.warning("No updatable parameters found in model")
            }

            // Extract each parameter
            for key in parameterKeys {
                if let value = try? extractParameter(from: model, key: key) {
                    weights[key] = value
                }
            }

            logger.debug("Extracted \(weights.count) parameter arrays from \(parameterKeys.count) keys")

        } catch let error as OctomilError {
            throw error
        } catch {
            logger.error("Failed to extract weights: \(error.localizedDescription)")
            throw OctomilError.weightExtractionFailed(reason: error.localizedDescription)
        }

        return weights
    }

    /// Extracts updatable parameter keys from the model description.
    ///
    /// For updatable CoreML models, `trainingInputDescriptionsByName` contains
    /// the feature names used during training. The updatable layer weights are
    /// accessible via `MLParameterKey` with the layer name.
    private func extractParameterKeys(from description: MLModelDescription) -> [String] {
        var keys: [String] = []

        // isUpdatable tells us if the model supports on-device training
        guard description.isUpdatable else {
            return keys
        }

        // trainingInputDescriptionsByName gives us the training feature names
        // (inputs the model expects during training, e.g., "input" and "target")
        // The actual updatable layer names come from parameterDescriptionsByKey
        // parameterDescriptionsByKey is available iOS 14+
        for (key, _) in description.parameterDescriptionsByKey {
            keys.append(key.description)
        }

        // Fallback: if no keys found via parameterDescriptionsByKey,
        // use the training input descriptions to infer layer names.
        if keys.isEmpty {
            // Common naming convention: layers in updatable models are named
            // with descriptive prefixes. We scan for known patterns.
            let layerPrefixes = ["dense", "conv", "lstm", "gru", "embedding", "fc", "linear"]
            let suffixes = [".weight", ".bias", "_weight", "_bias"]

            for (name, _) in description.inputDescriptionsByName {
                for prefix in layerPrefixes where name.hasPrefix(prefix) {
                    for suffix in suffixes {
                        keys.append(name + suffix)
                    }
                }
            }
        }

        return keys
    }

    /// Extracts a specific parameter from the model.
    ///
    /// On iOS 16+, uses `MLModel.parameterValue(for:)`.
    /// On older systems, attempts to read from the model's prediction output
    /// as a fallback (limited support).
    /// Extracts a specific parameter from the model using `parameterValue(for:)`.
    /// Available on iOS 14+ / macOS 11+ for updatable models.
    private func extractParameter(from model: MLModel, key: String) throws -> MLMultiArray {
        // Try weights scoped to this key
        let paramKey = MLParameterKey.weights.scoped(to: key)
        if let value = try? model.parameterValue(for: paramKey) as? MLMultiArray {
            return value
        }

        // Try bias scoped to this key
        let biasKey = MLParameterKey.biases.scoped(to: key)
        if let value = try? model.parameterValue(for: biasKey) as? MLMultiArray {
            return value
        }

        throw OctomilError.weightExtractionFailed(
            reason: "Cannot extract parameter '\(key)' — model may not expose this parameter"
        )
    }

    /// Computes delta between original and updated weights.
    func computeDelta(
        original: [String: MLMultiArray],
        updated: [String: MLMultiArray]
    ) -> [String: MLMultiArray] {
        var delta: [String: MLMultiArray] = [:]

        for (key, updatedArray) in updated {
            guard let originalArray = original[key] else {
                // If parameter doesn't exist in original, use full updated value
                delta[key] = updatedArray
                continue
            }

            // Compute difference
            if let differenceArray = subtractArrays(updatedArray, originalArray) {
                delta[key] = differenceArray
            }
        }

        return delta
    }

    /// Subtracts two MLMultiArrays element-wise.
    func subtractArrays(_ a: MLMultiArray, _ b: MLMultiArray) -> MLMultiArray? {
        guard a.shape == b.shape else {
            return nil
        }

        let count = a.count
        guard let result = try? MLMultiArray(shape: a.shape, dataType: a.dataType) else {
            return nil
        }

        for i in 0..<count {
            let aValue = a[i].doubleValue
            let bValue = b[i].doubleValue
            result[i] = NSNumber(value: aValue - bValue)
        }

        return result
    }

    /// Serializes weight delta to PyTorch-compatible format.
    ///
    /// Serializes to a simple format that can be loaded by PyTorch:
    /// - Header: Magic number, version, parameter count
    /// - For each parameter: name length, name, shape, data
    func serializeToPyTorch(delta: [String: MLMultiArray]) throws -> Data {
        var data = Data()

        // Write magic number (0x50545448 = "PTTH" for PyTorch)
        let magic: UInt32 = 0x50545448
        data.append(contentsOf: withUnsafeBytes(of: magic.bigEndian) { Array($0) })

        // Write version (1)
        let version: UInt32 = 1
        data.append(contentsOf: withUnsafeBytes(of: version.bigEndian) { Array($0) })

        // Write parameter count
        let paramCount = UInt32(delta.count)
        data.append(contentsOf: withUnsafeBytes(of: paramCount.bigEndian) { Array($0) })

        // Write each parameter
        for (name, array) in delta.sorted(by: { $0.key < $1.key }) {
            // Write parameter name
            let nameData = name.data(using: .utf8)!
            let nameLength = UInt32(nameData.count)
            data.append(contentsOf: withUnsafeBytes(of: nameLength.bigEndian) { Array($0) })
            data.append(nameData)

            // Write shape
            let shapeCount = UInt32(array.shape.count)
            data.append(contentsOf: withUnsafeBytes(of: shapeCount.bigEndian) { Array($0) })
            for dim in array.shape {
                let dimValue = UInt32(truncating: dim)
                data.append(contentsOf: withUnsafeBytes(of: dimValue.bigEndian) { Array($0) })
            }

            // Write data type (0 = float32, 1 = float64, 2 = int32, 3 = int64)
            let dataType: UInt32 = {
                switch array.dataType {
                case .float32, .float16: return 0
                case .double: return 1
                case .int32: return 2
                default: return 0
                }
            }()
            data.append(contentsOf: withUnsafeBytes(of: dataType.bigEndian) { Array($0) })

            // Write array data
            let arrayData = try serializeMLMultiArray(array)
            let dataLength = UInt32(arrayData.count)
            data.append(contentsOf: withUnsafeBytes(of: dataLength.bigEndian) { Array($0) })
            data.append(arrayData)
        }

        return data
    }

    /// Serializes an MLMultiArray to binary format.
    func serializeMLMultiArray(_ array: MLMultiArray) throws -> Data {
        var data = Data()

        // Convert all values to Float32 for consistency
        let count = array.count
        data.reserveCapacity(count * 4) // 4 bytes per float32

        for i in 0..<count {
            let value = array[i].floatValue
            data.append(contentsOf: withUnsafeBytes(of: value) { Array($0) })
        }

        return data
    }
}

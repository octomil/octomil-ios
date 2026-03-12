import Foundation
import CoreML
import os.log

/// Loads CoreML models with an automatic fallback chain across compute units.
///
/// The fallback chain tries progressively simpler compute configurations:
/// `.all` (ANE + GPU + CPU) -> `.cpuAndGPU` -> `.cpuOnly`.
/// If all fail, throws the last error.
public actor AdaptiveModelLoader {

    // MARK: - Errors

    /// Error thrown when all compute unit configurations fail to load the model.
    public enum LoadError: Error, LocalizedError {
        /// All compute unit configurations failed. Contains the errors from each attempt.
        case allComputeUnitsFailed(errors: [(MLComputeUnits, Error)])

        public var errorDescription: String? {
            switch self {
            case .allComputeUnitsFailed(let errors):
                let descriptions = errors.map { "  \(computeUnitsName($0.0)): \($0.1.localizedDescription)" }
                return "Failed to load model with any compute units:\n" + descriptions.joined(separator: "\n")
            }
        }

        private func computeUnitsName(_ units: MLComputeUnits) -> String {
            switch units {
            case .all: return "all (ANE+GPU+CPU)"
            case .cpuAndGPU: return "cpuAndGPU"
            case .cpuOnly: return "cpuOnly"
            case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
            @unknown default: return "unknown"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "AdaptiveModelLoader")

    /// The ordered fallback chain of compute units to try.
    private static let fallbackChain: [MLComputeUnits] = [.all, .cpuAndGPU, .cpuOnly]

    // MARK: - Public API

    public init() {}

    /// Loads a compiled CoreML model with automatic fallback through compute units.
    ///
    /// - Parameters:
    ///   - url: URL to the compiled model (`.mlmodelc`).
    ///   - preferredComputeUnits: Preferred starting point in the fallback chain.
    ///     If not `.all`, the chain starts from this preference.
    /// - Returns: The loaded `MLModel` and the compute units it was loaded with.
    /// - Throws: ``LoadError/allComputeUnitsFailed`` if no configuration works.
    public func load(
        from url: URL,
        preferredComputeUnits: MLComputeUnits = .all
    ) async throws -> (MLModel, MLComputeUnits) {
        let chain = buildFallbackChain(startingFrom: preferredComputeUnits)
        var errors: [(MLComputeUnits, Error)] = []

        for units in chain {
            do {
                let model = try loadModel(from: url, computeUnits: units)
                logger.info("Model loaded successfully with compute units: \(self.computeUnitsName(units))")
                return (model, units)
            } catch {
                logger.warning("Failed to load model with \(self.computeUnitsName(units)): \(error.localizedDescription)")
                errors.append((units, error))
            }
        }

        throw LoadError.allComputeUnitsFailed(errors: errors)
    }

    /// Reloads a model from its URL with different compute units.
    ///
    /// Used for runtime adaptation when device conditions change and require
    /// a different compute strategy.
    ///
    /// - Parameters:
    ///   - model: The currently loaded model (unused, present for API clarity).
    ///   - url: URL to the compiled model.
    ///   - computeUnits: The new compute units to use.
    /// - Returns: A newly loaded `MLModel` configured for the specified compute units.
    /// - Throws: If loading fails with the specified compute units.
    public func reload(
        model: MLModel,
        from url: URL,
        computeUnits: MLComputeUnits
    ) async throws -> MLModel {
        let newModel = try loadModel(from: url, computeUnits: computeUnits)
        logger.info("Model reloaded with compute units: \(self.computeUnitsName(computeUnits))")
        return newModel
    }

    // MARK: - Private

    private func loadModel(from url: URL, computeUnits: MLComputeUnits) throws -> MLModel {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        return try MLModel(contentsOf: url, configuration: config)
    }

    /// Builds a fallback chain starting from the preferred compute units.
    /// Skips any units that come before the preferred one in the standard chain.
    private func buildFallbackChain(startingFrom preferred: MLComputeUnits) -> [MLComputeUnits] {
        guard let index = Self.fallbackChain.firstIndex(of: preferred) else {
            // If preferred is not in our chain (e.g. cpuAndNeuralEngine), prepend it
            return [preferred] + Self.fallbackChain
        }
        return Array(Self.fallbackChain[index...])
    }

    private nonisolated func computeUnitsName(_ units: MLComputeUnits) -> String {
        switch units {
        case .all: return "all"
        case .cpuAndGPU: return "cpuAndGPU"
        case .cpuOnly: return "cpuOnly"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        @unknown default: return "unknown"
        }
    }
}

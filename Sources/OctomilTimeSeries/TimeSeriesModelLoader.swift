import Foundation
import MLXTimeSeries
import Octomil

/// Wraps MLX-Swift-TS model loading from HuggingFace Hub or local directory.
@available(iOS 17.0, macOS 14.0, *)
public actor TimeSeriesModelLoader {

    private var loadedModels: [String: TimeSeriesForecaster] = [:]

    public init() {}

    /// Load a time series model from HuggingFace Hub.
    /// - Parameter modelId: HuggingFace model ID (e.g. "mlx-community/toto-4bit").
    /// - Returns: A loaded ``TimeSeriesForecaster``.
    public func loadModel(modelId: String) async throws -> TimeSeriesForecaster {
        if let cached = loadedModels[modelId] {
            return cached
        }

        let forecaster = try await TimeSeriesForecaster.loadFromHub(id: modelId)
        loadedModels[modelId] = forecaster
        return forecaster
    }

    /// Load a time series model from a local directory.
    /// - Parameter directory: Path to directory containing config.json and safetensors.
    /// - Returns: A loaded ``TimeSeriesForecaster``.
    public func loadFromDirectory(_ directory: URL) throws -> TimeSeriesForecaster {
        let key = directory.absoluteString
        if let cached = loadedModels[key] {
            return cached
        }

        let forecaster = try TimeSeriesForecaster.loadFromDirectory(directory)
        loadedModels[key] = forecaster
        return forecaster
    }

    /// Evict a model from the in-memory cache.
    public func evict(modelId: String) {
        loadedModels.removeValue(forKey: modelId)
    }

    /// Evict all cached models.
    public func evictAll() {
        loadedModels.removeAll()
    }
}

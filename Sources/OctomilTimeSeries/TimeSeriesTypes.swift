import Foundation
import MLX
import MLXTimeSeries
import Octomil

/// Input for time series forecasting via Octomil SDK.
@available(iOS 17.0, macOS 14.0, *)
public struct OctomilTimeSeriesInput: Sendable {
    /// Historical context values (univariate).
    public let values: [Float]

    /// Number of future steps to predict.
    public let predictionLength: Int

    /// Model identifier (HuggingFace or local path).
    public let modelId: String

    public init(values: [Float], predictionLength: Int, modelId: String) {
        self.values = values
        self.predictionLength = predictionLength
        self.modelId = modelId
    }

    /// Convert to MLXTimeSeries input format.
    internal func toMLXInput() -> MLXTimeSeries.TimeSeriesInput {
        return .univariate(values)
    }
}

/// Forecast output from time series prediction.
@available(iOS 17.0, macOS 14.0, *)
public struct TimeSeriesForecast: Codable, Sendable {
    /// Mean predicted values.
    public let mean: [Float]

    /// Number of predicted steps.
    public let predictionLength: Int

    /// Model used for inference.
    public let modelId: String

    public init(mean: [Float], predictionLength: Int, modelId: String) {
        self.mean = mean
        self.predictionLength = predictionLength
        self.modelId = modelId
    }

    /// Create from an MLXTimeSeries prediction.
    internal init(prediction: TimeSeriesPrediction, modelId: String) {
        let meanArray = prediction.mean.flattened()
        self.mean = meanArray.asArray(Float.self)
        self.predictionLength = prediction.predictionLength
        self.modelId = modelId
    }
}

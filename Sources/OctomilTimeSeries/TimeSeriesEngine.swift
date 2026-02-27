import Foundation
import MLXTimeSeries
import Octomil

/// MLX-backed time series forecasting engine conforming to ``StreamingInferenceEngine``.
///
/// Emits a single ``InferenceChunk`` containing a JSON-encoded ``TimeSeriesForecast``.
/// Uses the `.timeSeries` modality.
@available(iOS 17.0, macOS 14.0, *)
public final class TimeSeriesEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let loader: TimeSeriesModelLoader

    public init(loader: TimeSeriesModelLoader = .init()) {
        self.loader = loader
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let forecast = try await self.runForecast(input: input)

                    let data = try JSONEncoder().encode(forecast)
                    let chunk = InferenceChunk(
                        index: 0,
                        data: data,
                        modality: .timeSeries,
                        timestamp: Date(),
                        latencyMs: 0
                    )
                    continuation.yield(chunk)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private func runForecast(input: Any) async throws -> TimeSeriesForecast {
        guard let tsInput = input as? OctomilTimeSeriesInput else {
            throw TimeSeriesError.invalidInput(
                "Expected OctomilTimeSeriesInput, got \(type(of: input))"
            )
        }

        guard !tsInput.values.isEmpty else {
            throw TimeSeriesError.invalidInput("Context values must not be empty")
        }

        let forecaster = try await loader.loadModel(modelId: tsInput.modelId)
        let mlxInput = tsInput.toMLXInput()
        let prediction = forecaster.forecast(input: mlxInput, predictionLength: tsInput.predictionLength)

        return TimeSeriesForecast(prediction: prediction, modelId: tsInput.modelId)
    }
}

/// Errors specific to time series inference.
public enum TimeSeriesError: Error, LocalizedError {
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason):
            return "Time series input error: \(reason)"
        }
    }
}

import Foundation
import Octomil

@available(iOS 17.0, macOS 14.0, *)
extension EngineRegistry {

    /// Register the time series forecasting engine as the default for `.timeSeries` modality.
    ///
    /// This overrides the built-in placeholder (LLMEngine) with a real
    /// ``TimeSeriesEngine`` backed by the provided ``TimeSeriesModelLoader``.
    ///
    /// - Parameter loader: The ``TimeSeriesModelLoader`` used for forecast model loading.
    public func registerTimeSeries(loader: TimeSeriesModelLoader) {
        register(modality: .timeSeries) { _ in
            TimeSeriesEngine(loader: loader)
        }
    }
}

import Foundation
import XCTest
@testable import OctomilTimeSeries
@testable import Octomil

@available(iOS 17.0, macOS 14.0, *)
final class TimeSeriesEngineTests: XCTestCase {

    // MARK: - OctomilTimeSeriesInput

    func testTimeSeriesInputProperties() {
        let input = OctomilTimeSeriesInput(
            values: [1.0, 2.0, 3.0, 4.0, 5.0],
            predictionLength: 3,
            modelId: "test-model"
        )

        XCTAssertEqual(input.values, [1.0, 2.0, 3.0, 4.0, 5.0])
        XCTAssertEqual(input.predictionLength, 3)
        XCTAssertEqual(input.modelId, "test-model")
    }

    func testTimeSeriesInputConvertsToMLX() {
        let input = OctomilTimeSeriesInput(
            values: [1.0, 2.0, 3.0],
            predictionLength: 2,
            modelId: "test"
        )

        let mlxInput = input.toMLXInput()
        // MLX input should have shape [1, 1, 3] for univariate
        XCTAssertEqual(mlxInput.series.shape, [1, 1, 3])
    }

    // MARK: - TimeSeriesForecast

    func testTimeSeriesForecastCodableRoundtrip() throws {
        let forecast = TimeSeriesForecast(
            mean: [1.0, 2.0, 3.0],
            predictionLength: 3,
            modelId: "test-model"
        )

        let data = try JSONEncoder().encode(forecast)
        let decoded = try JSONDecoder().decode(TimeSeriesForecast.self, from: data)

        XCTAssertEqual(decoded.mean, forecast.mean)
        XCTAssertEqual(decoded.predictionLength, forecast.predictionLength)
        XCTAssertEqual(decoded.modelId, forecast.modelId)
    }

    func testTimeSeriesForecastProperties() {
        let forecast = TimeSeriesForecast(
            mean: [10.0, 20.0],
            predictionLength: 2,
            modelId: "m1"
        )

        XCTAssertEqual(forecast.mean.count, 2)
        XCTAssertEqual(forecast.predictionLength, 2)
    }

    // MARK: - TimeSeriesError

    func testTimeSeriesErrorDescription() {
        let error = TimeSeriesError.invalidInput("empty values")
        XCTAssertEqual(error.errorDescription, "Time series input error: empty values")
    }

    // MARK: - TimeSeriesEngine Protocol Conformance

    func testTimeSeriesEngineConformsToStreamingInferenceEngine() {
        let _: StreamingInferenceEngine.Type = TimeSeriesEngine.self
    }

    func testTimeSeriesEngineInitialization() {
        let engine = TimeSeriesEngine()
        XCTAssertNotNil(engine)
    }

    // MARK: - Invalid Input Handling

    func testTimeSeriesEngineRejectsNonTimeSeriesInput() async {
        let engine = TimeSeriesEngine()
        let stream = engine.generate(input: "not a time series input", modality: .timeSeries)

        do {
            for try await _ in stream {
                XCTFail("Should have thrown an error")
            }
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is TimeSeriesError)
            if case TimeSeriesError.invalidInput(let reason) = error {
                XCTAssertTrue(reason.contains("OctomilTimeSeriesInput"))
            }
        }
    }
}

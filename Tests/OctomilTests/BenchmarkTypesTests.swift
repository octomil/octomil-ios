import Foundation
import XCTest
@testable import Octomil

final class BenchmarkTypesTests: XCTestCase {

    // MARK: - BenchmarkResult Construction

    func testBenchmarkResultOkWhenNoError() {
        let result = BenchmarkResult(
            engineName: "mlx",
            tokensPerSecond: 85.0,
            ttftMs: 120.0,
            memoryMb: 512.0,
            error: nil,
            metadata: nil
        )

        XCTAssertTrue(result.ok)
        XCTAssertNil(result.error)
    }

    func testBenchmarkResultNotOkWhenError() {
        let result = BenchmarkResult(
            engineName: "coreml",
            tokensPerSecond: 0.0,
            ttftMs: 0.0,
            memoryMb: 0.0,
            error: "Model format not supported",
            metadata: nil
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Model format not supported")
    }

    func testBenchmarkResultWithMetadata() {
        let meta = ["device": "iPhone 16 Pro", "chip": "A18 Pro"]
        let result = BenchmarkResult(
            engineName: "mlx",
            tokensPerSecond: 90.0,
            ttftMs: 95.0,
            memoryMb: 480.0,
            error: nil,
            metadata: meta
        )

        XCTAssertEqual(result.metadata?["device"], "iPhone 16 Pro")
        XCTAssertEqual(result.metadata?["chip"], "A18 Pro")
    }

    // MARK: - BenchmarkResult Codable

    func testBenchmarkResultCodableRoundTrip() throws {
        let result = BenchmarkResult(
            engineName: "mlx",
            tokensPerSecond: 72.5,
            ttftMs: 150.0,
            memoryMb: 1024.0,
            error: nil,
            metadata: ["variant": "4bit"]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(BenchmarkResult.self, from: data)

        XCTAssertEqual(decoded.engineName, "mlx")
        XCTAssertEqual(decoded.tokensPerSecond, 72.5)
        XCTAssertEqual(decoded.ttftMs, 150.0)
        XCTAssertEqual(decoded.memoryMb, 1024.0)
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decoded.metadata?["variant"], "4bit")
        XCTAssertTrue(decoded.ok)
    }

    func testBenchmarkResultSnakeCaseKeys() throws {
        let result = BenchmarkResult(
            engineName: "test",
            tokensPerSecond: 50.0,
            ttftMs: 200.0,
            memoryMb: 256.0
        )

        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["engine_name"])
        XCTAssertNotNil(json["tokens_per_second"])
        XCTAssertNotNil(json["ttft_ms"])
        XCTAssertNotNil(json["memory_mb"])
        // camelCase should NOT be present
        XCTAssertNil(json["engineName"])
        XCTAssertNil(json["tokensPerSecond"])
    }

    func testBenchmarkResultWithErrorCodableRoundTrip() throws {
        let result = BenchmarkResult(
            engineName: "coreml",
            tokensPerSecond: 0.0,
            ttftMs: 0.0,
            memoryMb: 0.0,
            error: "Timeout"
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(BenchmarkResult.self, from: data)

        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(decoded.error, "Timeout")
    }

    // MARK: - DetectionResult

    func testDetectionResultConstruction() {
        let result = DetectionResult(engine: .mlx, available: true, info: "Metal 3, 10 GPU cores")

        XCTAssertEqual(result.engine, .mlx)
        XCTAssertTrue(result.available)
        XCTAssertEqual(result.info, "Metal 3, 10 GPU cores")
    }

    func testDetectionResultUnavailable() {
        let result = DetectionResult(engine: .coreml, available: false, info: nil)

        XCTAssertEqual(result.engine, .coreml)
        XCTAssertFalse(result.available)
        XCTAssertNil(result.info)
    }

    // MARK: - RankedEngine

    func testRankedEngineConstruction() {
        let benchResult = BenchmarkResult(
            engineName: "mlx",
            tokensPerSecond: 100.0,
            ttftMs: 80.0,
            memoryMb: 768.0
        )
        let ranked = RankedEngine(engine: .mlx, result: benchResult)

        XCTAssertEqual(ranked.engine, .mlx)
        XCTAssertEqual(ranked.result.tokensPerSecond, 100.0)
        XCTAssertTrue(ranked.result.ok)
    }

    // MARK: - EngineRegistry Stubs

    func testDetectAllReturnsResults() {
        let registry = EngineRegistry()
        let results = registry.detectAll(modality: .text)
        XCTAssertFalse(results.isEmpty)
        // Stub returns all engines as unavailable
        for result in results {
            XCTAssertFalse(result.available)
        }
    }

    func testBenchmarkAllReturnsEmptyStub() async {
        let registry = EngineRegistry()
        let url = URL(fileURLWithPath: "/tmp/model.safetensors")
        let ranked = await registry.benchmarkAll(modality: .text, modelURL: url)
        XCTAssertTrue(ranked.isEmpty)
    }

    func testSelectBestReturnsFirstOk() {
        let registry = EngineRegistry()
        let fail = RankedEngine(
            engine: .coreml,
            result: BenchmarkResult(engineName: "coreml", tokensPerSecond: 0, ttftMs: 0, memoryMb: 0, error: "fail")
        )
        let ok = RankedEngine(
            engine: .mlx,
            result: BenchmarkResult(engineName: "mlx", tokensPerSecond: 80, ttftMs: 100, memoryMb: 512)
        )
        let best = registry.selectBest([fail, ok])
        XCTAssertEqual(best?.engine, .mlx)
    }

    func testSelectBestReturnsNilWhenAllFail() {
        let registry = EngineRegistry()
        let fail1 = RankedEngine(
            engine: .coreml,
            result: BenchmarkResult(engineName: "coreml", tokensPerSecond: 0, ttftMs: 0, memoryMb: 0, error: "err")
        )
        let fail2 = RankedEngine(
            engine: .mlx,
            result: BenchmarkResult(engineName: "mlx", tokensPerSecond: 0, ttftMs: 0, memoryMb: 0, error: "err")
        )
        let best = registry.selectBest([fail1, fail2])
        XCTAssertNil(best)
    }

    func testSelectBestReturnsNilForEmpty() {
        let registry = EngineRegistry()
        let best = registry.selectBest([])
        XCTAssertNil(best)
    }
}

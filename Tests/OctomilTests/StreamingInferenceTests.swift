import Foundation
import XCTest
@testable import Octomil

/// Tests for ``Modality``, ``InferenceChunk``, ``StreamingInferenceResult``,
/// and ``InstrumentedStreamWrapper``.
final class StreamingInferenceTests: XCTestCase {

    // MARK: - Modality

    func testModalityAllCases() {
        let cases = Modality.allCases
        XCTAssertEqual(cases.count, 5)
        XCTAssertTrue(cases.contains(.text))
        XCTAssertTrue(cases.contains(.image))
        XCTAssertTrue(cases.contains(.audio))
        XCTAssertTrue(cases.contains(.video))
        XCTAssertTrue(cases.contains(.timeSeries))
    }

    func testModalityRawValues() {
        XCTAssertEqual(Modality.text.rawValue, "text")
        XCTAssertEqual(Modality.image.rawValue, "image")
        XCTAssertEqual(Modality.audio.rawValue, "audio")
        XCTAssertEqual(Modality.video.rawValue, "video")
        XCTAssertEqual(Modality.timeSeries.rawValue, "time_series")
    }

    func testModalityCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for modality in Modality.allCases {
            let data = try encoder.encode(modality)
            let decoded = try decoder.decode(Modality.self, from: data)
            XCTAssertEqual(decoded, modality)
        }
    }

    // MARK: - InferenceChunk

    func testInferenceChunkProperties() {
        let now = Date()
        let chunkData = Data("hello".utf8)
        let chunk = InferenceChunk(
            index: 3,
            data: chunkData,
            modality: .text,
            timestamp: now,
            latencyMs: 12.5
        )

        XCTAssertEqual(chunk.index, 3)
        XCTAssertEqual(chunk.data, chunkData)
        XCTAssertEqual(chunk.modality, .text)
        XCTAssertEqual(chunk.timestamp, now)
        XCTAssertEqual(chunk.latencyMs, 12.5)
    }

    // MARK: - StreamingInferenceResult Codable

    func testStreamingInferenceResultCodableRoundtrip() throws {
        let result = StreamingInferenceResult(
            sessionId: "session-123",
            modality: .text,
            ttfcMs: 42.0,
            avgChunkLatencyMs: 5.5,
            totalChunks: 10,
            totalDurationMs: 97.0,
            throughput: 103.1
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(StreamingInferenceResult.self, from: data)

        XCTAssertEqual(decoded.sessionId, "session-123")
        XCTAssertEqual(decoded.modality, .text)
        XCTAssertEqual(decoded.ttfcMs, 42.0)
        XCTAssertEqual(decoded.avgChunkLatencyMs, 5.5)
        XCTAssertEqual(decoded.totalChunks, 10)
        XCTAssertEqual(decoded.totalDurationMs, 97.0)
        XCTAssertEqual(decoded.throughput, 103.1)
    }

    func testStreamingInferenceResultCodingKeys() throws {
        let result = StreamingInferenceResult(
            sessionId: "s1",
            modality: .audio,
            ttfcMs: 1,
            avgChunkLatencyMs: 2,
            totalChunks: 3,
            totalDurationMs: 4,
            throughput: 5
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify snake_case keys
        XCTAssertNotNil(json["session_id"])
        XCTAssertNotNil(json["ttfc_ms"])
        XCTAssertNotNil(json["avg_chunk_latency_ms"])
        XCTAssertNotNil(json["total_chunks"])
        XCTAssertNotNil(json["total_duration_ms"])
        XCTAssertNotNil(json["throughput"])
        XCTAssertNotNil(json["modality"])
    }

    // MARK: - InstrumentedStreamWrapper with MockStreamingEngine

    func testWrapperCountsChunks() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = [
            .init("one"),
            .init("two"),
            .init("three"),
        ]

        let wrapper = InstrumentedStreamWrapper(sessionId: "test-session", modality: .text)
        let (stream, getResult) = wrapper.wrap(engine, input: "prompt")

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 3)

        let result = getResult()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.totalChunks, 3)
        XCTAssertEqual(result?.sessionId, "test-session")
        XCTAssertEqual(result?.modality, .text)
    }

    func testWrapperComputesTTFC() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = [
            .init("first", delayMs: 20),
            .init("second", delayMs: 5),
        ]

        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, getResult) = wrapper.wrap(engine, input: "prompt")

        for try await _ in stream { /* No-op: drain stream */ }

        let result = try XCTUnwrap(getResult())
        // TTFC should be >= 20ms (the delay for the first chunk)
        XCTAssertGreaterThan(result.ttfcMs, 10)
        XCTAssertEqual(result.totalChunks, 2)
    }

    func testWrapperComputesThroughput() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = (0..<5).map { MockStreamingEngine.ChunkSpec("c\($0)", delayMs: 5) }

        let wrapper = InstrumentedStreamWrapper(modality: .image)
        let (stream, getResult) = wrapper.wrap(engine, input: "prompt")

        for try await _ in stream { /* No-op: drain stream */ }

        let result = try XCTUnwrap(getResult())
        XCTAssertEqual(result.totalChunks, 5)
        XCTAssertGreaterThan(result.throughput, 0)
        XCTAssertGreaterThan(result.totalDurationMs, 0)
    }

    func testWrapperEmptyStream() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = []

        let wrapper = InstrumentedStreamWrapper(modality: .audio)
        let (stream, getResult) = wrapper.wrap(engine, input: "empty")

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 0)

        let result = try XCTUnwrap(getResult())
        XCTAssertEqual(result.totalChunks, 0)
        XCTAssertEqual(result.avgChunkLatencyMs, 0)
    }

    func testWrapperErrorPropagation() async throws {
        struct TestError: Error {}

        let engine = MockStreamingEngine()
        engine.chunks = [.init("one")]
        engine.terminalError = TestError()

        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, _) = wrapper.wrap(engine, input: "error-test")

        var receivedChunks = 0
        do {
            for try await _ in stream {
                receivedChunks += 1
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestError)
        }
        XCTAssertEqual(receivedChunks, 1)
    }

    func testWrapperCancellation() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = (0..<100).map { MockStreamingEngine.ChunkSpec("c\($0)", delayMs: 10) }

        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, _) = wrapper.wrap(engine, input: "cancel-test")

        let task = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count >= 3 { break }
            }
            return count
        }

        let count = try await task.value
        // Should have received at least 3 chunks but not all 100
        XCTAssertGreaterThanOrEqual(count, 3)
        XCTAssertLessThan(count, 100)
    }

    func testWrapperChunkIndicesAreSequential() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = (0..<4).map { MockStreamingEngine.ChunkSpec("c\($0)") }

        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, _) = wrapper.wrap(engine, input: "index-test")

        var indices: [Int] = []
        for try await chunk in stream {
            indices.append(chunk.index)
        }

        XCTAssertEqual(indices, [0, 1, 2, 3])
    }

    func testWrapperChunkModalityMatchesConfiguration() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = [.init("one")]

        let wrapper = InstrumentedStreamWrapper(modality: .video)
        let (stream, _) = wrapper.wrap(engine, input: "test")

        for try await chunk in stream {
            XCTAssertEqual(chunk.modality, .video)
        }
    }

    func testWrapperThroughputWithinExpectedRange() async throws {
        // 5 chunks with 10ms delay each => total ~50ms => throughput ~100 chunks/sec
        // Formula: throughput = chunks / (totalDurationMs / 1000)
        let engine = MockStreamingEngine()
        engine.chunks = (0..<5).map { MockStreamingEngine.ChunkSpec("c\($0)", delayMs: 10) }

        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, getResult) = wrapper.wrap(engine, input: "throughput-test")

        for try await _ in stream { /* drain stream */ }

        let result = try XCTUnwrap(getResult())
        XCTAssertEqual(result.totalChunks, 5)

        // With 5 chunks and ~50ms total duration, throughput should be ~100 chunks/sec.
        // Allow generous bounds for CI variability: 20-500 chunks/sec.
        XCTAssertGreaterThan(result.throughput, 20.0,
                             "Throughput should be > 20 chunks/sec for 5 chunks with 10ms delays")
        XCTAssertLessThan(result.throughput, 500.0,
                          "Throughput should be < 500 chunks/sec (sanity upper bound)")

        // Verify the formula: throughput = totalChunks / (totalDurationMs / 1000)
        let expectedThroughput = Double(result.totalChunks) / (result.totalDurationMs / 1000)
        XCTAssertEqual(result.throughput, expectedThroughput, accuracy: 0.01,
                       "Throughput should match chunks / (totalDurationMs / 1000)")
    }

    func testWrapperAverageLatencyComputation() async throws {
        let engine = MockStreamingEngine()
        engine.chunks = [
            .init("a", delayMs: 10),
            .init("b", delayMs: 20),
            .init("c", delayMs: 30),
        ]

        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, getResult) = wrapper.wrap(engine, input: "latency-test")

        for try await _ in stream { /* No-op: drain stream */ }

        let result = try XCTUnwrap(getResult())
        // Average latency should be roughly (10 + 20 + 30) / 3 = 20ms
        // Allow generous tolerance for CI variability
        XCTAssertGreaterThan(result.avgChunkLatencyMs, 5)
    }
}

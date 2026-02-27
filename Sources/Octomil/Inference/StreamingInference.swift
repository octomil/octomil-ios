import Foundation

// MARK: - Modality

/// The modality of a generative model's output.
public enum Modality: String, Codable, Hashable, Sendable, CaseIterable {
    case text
    case image
    case audio
    case video
    case timeSeries = "time_series"
}

// MARK: - InferenceChunk

/// A single chunk produced during streaming inference.
///
/// Each chunk carries modality-specific payload data and timing information
/// that the SDK uses to compute TTFC and inter-chunk latency.
public struct InferenceChunk: Sendable {
    /// Zero-based index of this chunk within the generation session.
    public let index: Int

    /// Modality-specific payload (e.g. UTF-8 token bytes, pixel data, audio samples).
    public let data: Data

    /// The modality this chunk belongs to.
    public let modality: Modality

    /// Absolute timestamp when the chunk was produced.
    public let timestamp: Date

    /// Milliseconds elapsed since the previous chunk (or since session start for the first chunk).
    public let latencyMs: Double

    public init(index: Int, data: Data, modality: Modality, timestamp: Date, latencyMs: Double) {
        self.index = index
        self.data = data
        self.modality = modality
        self.timestamp = timestamp
        self.latencyMs = latencyMs
    }
}

// MARK: - StreamingInferenceResult

/// Aggregated metrics for a completed streaming inference session.
public struct StreamingInferenceResult: Sendable, Codable {
    /// Client-generated UUID grouping all chunks from one generation.
    public let sessionId: String

    /// The modality of the generation.
    public let modality: Modality

    /// Time to first chunk in milliseconds.
    public let ttfcMs: Double

    /// Average inter-chunk latency in milliseconds.
    public let avgChunkLatencyMs: Double

    /// Total number of chunks produced.
    public let totalChunks: Int

    /// Wall-clock duration of the entire generation in milliseconds.
    public let totalDurationMs: Double

    /// Throughput in chunks per second.
    public let throughput: Double

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case modality
        case ttfcMs = "ttfc_ms"
        case avgChunkLatencyMs = "avg_chunk_latency_ms"
        case totalChunks = "total_chunks"
        case totalDurationMs = "total_duration_ms"
        case throughput
    }
}

// MARK: - StreamingInferenceEngine

/// Protocol that all modality-specific inference engines conform to.
///
/// Implementors produce an ``AsyncThrowingStream`` of ``InferenceChunk``
/// values. The SDK wraps each chunk with timing instrumentation.
public protocol StreamingInferenceEngine: Sendable {
    /// Generate output for the given input, streaming chunks back to the caller.
    ///
    /// - Parameters:
    ///   - input: Modality-specific input (prompt string, conditioning image, etc.).
    ///   - modality: The output modality.
    /// - Returns: An async stream of inference chunks.
    func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error>
}

// MARK: - Timing Wrapper

/// Wraps a raw engine stream with per-chunk timing instrumentation and
/// produces a ``StreamingInferenceResult`` upon completion.
public final class InstrumentedStreamWrapper: @unchecked Sendable {

    private let sessionId: String
    private let modality: Modality
    private let modelId: String?

    public init(sessionId: String = UUID().uuidString, modality: Modality, modelId: String? = nil) {
        self.sessionId = sessionId
        self.modality = modality
        self.modelId = modelId
    }

    /// Wraps an engine's raw chunk stream, adding timing to each chunk.
    ///
    /// The returned tuple contains the instrumented stream and a closure
    /// that, when called after the stream completes, returns the aggregated
    /// result.
    public func wrap(
        _ engine: StreamingInferenceEngine,
        input: Any
    ) -> (stream: AsyncThrowingStream<InferenceChunk, Error>, result: @Sendable () -> StreamingInferenceResult?) {

        let sessionId = self.sessionId
        let modality = self.modality

        // Shared mutable state protected by the serial nature of the stream consumer.
        final class State: @unchecked Sendable {
            var sessionStart: Date?
            var firstChunkTime: Date?
            var previousChunkTime: Date?
            var latencies: [Double] = []
            var chunkCount = 0
            var result: StreamingInferenceResult?
        }

        let state = State()

        let rawStream = engine.generate(input: input, modality: modality)

        let modelId = self.modelId

        let timedStream = AsyncThrowingStream<InferenceChunk, Error> { continuation in
            let task = Task {
                let start = Date()
                state.sessionStart = start
                state.previousChunkTime = start

                // Record inference started telemetry
                if let modelId = modelId {
                    TelemetryQueue.shared?.recordStarted(modelId: modelId)
                }

                do {
                    for try await rawChunk in rawStream {
                        let now = Date()

                        if state.firstChunkTime == nil {
                            state.firstChunkTime = now
                        }

                        let latencyMs = now.timeIntervalSince(state.previousChunkTime ?? start) * 1000
                        state.previousChunkTime = now
                        state.latencies.append(latencyMs)
                        state.chunkCount += 1

                        let chunk = InferenceChunk(
                            index: state.chunkCount - 1,
                            data: rawChunk.data,
                            modality: modality,
                            timestamp: now,
                            latencyMs: latencyMs
                        )

                        continuation.yield(chunk)
                    }

                    // Build result
                    let end = Date()
                    let totalDurationMs = end.timeIntervalSince(start) * 1000
                    let ttfcMs = (state.firstChunkTime ?? end).timeIntervalSince(start) * 1000
                    let avgLatency = state.latencies.isEmpty
                        ? 0.0
                        : state.latencies.reduce(0, +) / Double(state.latencies.count)
                    let throughput = totalDurationMs > 0
                        ? Double(state.chunkCount) / (totalDurationMs / 1000)
                        : 0.0

                    state.result = StreamingInferenceResult(
                        sessionId: sessionId,
                        modality: modality,
                        ttfcMs: ttfcMs,
                        avgChunkLatencyMs: avgLatency,
                        totalChunks: state.chunkCount,
                        totalDurationMs: totalDurationMs,
                        throughput: throughput
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return (timedStream, { state.result })
    }
}

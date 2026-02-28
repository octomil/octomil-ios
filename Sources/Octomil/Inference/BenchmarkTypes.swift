import Foundation

// MARK: - BenchmarkResult

/// Result of benchmarking a single engine on a specific model.
public struct BenchmarkResult: Sendable, Codable {
    /// Name of the engine that was benchmarked.
    public let engineName: String
    /// Tokens per second achieved during the benchmark.
    public let tokensPerSecond: Double
    /// Time to first token in milliseconds.
    public let ttftMs: Double
    /// Peak memory usage in megabytes.
    public let memoryMb: Double
    /// Error message if the benchmark failed.
    public let error: String?
    /// Arbitrary metadata (e.g. device info, model variant).
    public let metadata: [String: String]?

    /// Whether the benchmark completed without error.
    public var ok: Bool { error == nil }

    public init(
        engineName: String,
        tokensPerSecond: Double,
        ttftMs: Double,
        memoryMb: Double,
        error: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.engineName = engineName
        self.tokensPerSecond = tokensPerSecond
        self.ttftMs = ttftMs
        self.memoryMb = memoryMb
        self.error = error
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case engineName = "engine_name"
        case tokensPerSecond = "tokens_per_second"
        case ttftMs = "ttft_ms"
        case memoryMb = "memory_mb"
        case error
        case metadata
    }
}

// MARK: - DetectionResult

/// Result of detecting whether an engine is available on the current device.
public struct DetectionResult: Sendable {
    /// The engine that was probed.
    public let engine: Engine
    /// Whether the engine is available.
    public let available: Bool
    /// Human-readable info (e.g. "Metal 3, 8 GPU cores").
    public let info: String?

    public init(engine: Engine, available: Bool, info: String? = nil) {
        self.engine = engine
        self.available = available
        self.info = info
    }
}

// MARK: - RankedEngine

/// An engine paired with its benchmark result for ranking.
public struct RankedEngine: Sendable {
    /// The engine that was benchmarked.
    public let engine: Engine
    /// The benchmark result.
    public let result: BenchmarkResult

    public init(engine: Engine, result: BenchmarkResult) {
        self.engine = engine
        self.result = result
    }
}

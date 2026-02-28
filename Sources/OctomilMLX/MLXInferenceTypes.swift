import Foundation

// MARK: - InferenceMetrics

/// Per-generation metrics for MLX inference sessions.
public struct InferenceMetrics: Sendable, Codable {
    /// Time to first chunk in milliseconds.
    public let ttfcMs: Double
    /// Number of prompt tokens processed.
    public let promptTokens: Int
    /// Total tokens generated (prompt + completion).
    public let totalTokens: Int
    /// Tokens per second during generation.
    public let tokensPerSecond: Double
    /// Wall-clock duration in milliseconds.
    public let totalDurationMs: Double
    /// Whether the KV cache was reused from a previous generation.
    public let cacheHit: Bool
    /// The attention backend used (e.g. "metal", "sdpa").
    public let attentionBackend: String?

    public init(
        ttfcMs: Double,
        promptTokens: Int,
        totalTokens: Int,
        tokensPerSecond: Double,
        totalDurationMs: Double,
        cacheHit: Bool,
        attentionBackend: String? = nil
    ) {
        self.ttfcMs = ttfcMs
        self.promptTokens = promptTokens
        self.totalTokens = totalTokens
        self.tokensPerSecond = tokensPerSecond
        self.totalDurationMs = totalDurationMs
        self.cacheHit = cacheHit
        self.attentionBackend = attentionBackend
    }

    enum CodingKeys: String, CodingKey {
        case ttfcMs = "ttfc_ms"
        case promptTokens = "prompt_tokens"
        case totalTokens = "total_tokens"
        case tokensPerSecond = "tokens_per_second"
        case totalDurationMs = "total_duration_ms"
        case cacheHit = "cache_hit"
        case attentionBackend = "attention_backend"
    }
}

// MARK: - GenerationChunk

/// A single chunk produced during MLX generation with token-level detail.
public struct GenerationChunk: Sendable {
    /// Decoded text for this chunk.
    public let text: String
    /// Number of tokens in this chunk.
    public let tokenCount: Int
    /// Current tokens-per-second throughput.
    public let tokensPerSecond: Double
    /// Reason generation stopped, if this is the final chunk.
    public let finishReason: String?

    public init(text: String, tokenCount: Int, tokensPerSecond: Double, finishReason: String? = nil) {
        self.text = text
        self.tokenCount = tokenCount
        self.tokensPerSecond = tokensPerSecond
        self.finishReason = finishReason
    }
}

// MARK: - CacheStats

/// Aggregated KV cache hit/miss statistics.
public struct CacheStats: Sendable, Codable {
    /// Total cache hits.
    public let hits: Int
    /// Total cache misses.
    public let misses: Int
    /// Hit rate as a fraction in [0, 1].
    public let hitRate: Double
    /// Number of cached entries currently held.
    public let entries: Int
    /// Approximate memory usage in megabytes.
    public let memoryMb: Double

    public init(hits: Int, misses: Int, hitRate: Double, entries: Int, memoryMb: Double) {
        self.hits = hits
        self.misses = misses
        self.hitRate = hitRate
        self.entries = entries
        self.memoryMb = memoryMb
    }

    enum CodingKeys: String, CodingKey {
        case hits
        case misses
        case hitRate = "hit_rate"
        case entries
        case memoryMb = "memory_mb"
    }
}

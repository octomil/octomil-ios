// Auto-generated span event attribute key constants.

public enum SpanEventAttribute {
    public static let octomilTtftMs = "octomil.ttft_ms"
    public static let octomilChunkIndex = "octomil.chunk.index"
    public static let octomilChunkLatencyMs = "octomil.chunk.latency_ms"
    public static let octomilToolName = "octomil.tool.name"
    public static let octomilToolRound = "octomil.tool.round"
    public static let octomilFallbackReason = "octomil.fallback.reason"
    public static let octomilFallbackProvider = "octomil.fallback.provider"
    public static let octomilTokensTotal = "octomil.tokens.total"
    public static let octomilTokensPerSecond = "octomil.tokens.per_second"
    public static let octomilDurationMs = "octomil.duration_ms"
    public static let octomilDownloadUrl = "octomil.download.url"
    public static let octomilDownloadExpectedBytes = "octomil.download.expected_bytes"
    public static let octomilDownloadDurationMs = "octomil.download.duration_ms"
    public static let octomilDownloadBytes = "octomil.download.bytes"
    public static let octomilChecksumAlgorithm = "octomil.checksum.algorithm"
    public static let octomilRuntimeExecutor = "octomil.runtime.executor"
    public static let octomilRuntimeInitMs = "octomil.runtime.init_ms"

    public static let eventRequiredAttributes: [String: [String]] = [
        "first_token": ["octomil.ttft_ms"],
        "chunk_produced": ["octomil.chunk.index"],
        "tool_call_emitted": ["octomil.tool.name", "octomil.tool.round"],
        "fallback_triggered": ["octomil.fallback.reason"],
        "completed": ["octomil.tokens.total", "octomil.tokens.per_second", "octomil.duration_ms"],
        "download_started": [],
        "download_completed": ["octomil.download.duration_ms", "octomil.download.bytes"],
        "checksum_verified": [],
        "runtime_initialized": ["octomil.runtime.executor", "octomil.runtime.init_ms"],
    ]
}

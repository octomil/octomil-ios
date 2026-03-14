// Auto-generated span event name constants.

public enum SpanEventName {
    public static let firstToken = "first_token"
    public static let chunkProduced = "chunk_produced"
    public static let toolCallEmitted = "tool_call_emitted"
    public static let fallbackTriggered = "fallback_triggered"
    public static let completed = "completed"
    public static let downloadStarted = "download_started"
    public static let downloadCompleted = "download_completed"
    public static let checksumVerified = "checksum_verified"
    public static let runtimeInitialized = "runtime_initialized"

    public static let eventParentSpan: [String: String] = [
        "first_token": "octomil.response",
        "chunk_produced": "octomil.response",
        "tool_call_emitted": "octomil.response",
        "fallback_triggered": "octomil.response",
        "completed": "octomil.response",
        "download_started": "octomil.model.load",
        "download_completed": "octomil.model.load",
        "checksum_verified": "octomil.model.load",
        "runtime_initialized": "octomil.model.load",
    ]
}

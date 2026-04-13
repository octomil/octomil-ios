// Auto-generated span status mapping constants.

public enum SpanStatusMapping {
    public static let errorType = "error.type"
    public static let octomilErrorCode = "octomil.error.code"
    public static let octomilErrorRetryable = "octomil.error.retryable"
    public static let octomilErrorMessage = "octomil.error.message"

    public static let spanExpectedErrors: [String: [String]] = [
        "octomil.response": ["inference_failed", "model_load_failed", "insufficient_memory", "runtime_unavailable", "stream_interrupted", "context_too_large", "unsupported_modality", "cancelled", "app_backgrounded", "max_tool_rounds_exceeded", "policy_denied"],
        "octomil.model.load": ["model_not_found", "model_disabled", "version_not_found", "download_failed", "checksum_mismatch", "insufficient_storage", "insufficient_memory", "runtime_unavailable", "model_load_failed", "accelerator_unavailable"],
        "octomil.tool.execute": ["inference_failed", "cancelled", "max_tool_rounds_exceeded"],
        "octomil.fallback.cloud": ["network_unavailable", "request_timeout", "server_error", "rate_limited", "cloud_fallback_disallowed", "authentication_failed"],
        "octomil.control.refresh": ["control_sync_failed", "network_unavailable", "authentication_failed", "forbidden"],
        "octomil.control.heartbeat": ["control_sync_failed", "network_unavailable", "request_timeout"],
        "octomil.rollout.sync": ["control_sync_failed", "download_failed", "insufficient_storage", "network_unavailable"],
    ]
}

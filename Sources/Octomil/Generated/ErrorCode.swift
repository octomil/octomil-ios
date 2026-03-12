// Auto-generated from octomil-contracts. Do not edit.

/// Canonical error codes shared by all SDKs and the server.
/// Maps 1:1 to the `error_code` enum in octomil-contracts.
public enum ErrorCode: String, Codable, Sendable {
    case networkUnavailable = "network_unavailable"
    case requestTimeout = "request_timeout"
    case serverError = "server_error"
    case invalidApiKey = "invalid_api_key"
    case authenticationFailed = "authentication_failed"
    case forbidden = "forbidden"
    case modelNotFound = "model_not_found"
    case modelDisabled = "model_disabled"
    case downloadFailed = "download_failed"
    case checksumMismatch = "checksum_mismatch"
    case insufficientStorage = "insufficient_storage"
    case runtimeUnavailable = "runtime_unavailable"
    case modelLoadFailed = "model_load_failed"
    case inferenceFailed = "inference_failed"
    case insufficientMemory = "insufficient_memory"
    case rateLimited = "rate_limited"
    case invalidInput = "invalid_input"
    case cancelled = "cancelled"
    case unknown = "unknown"
}

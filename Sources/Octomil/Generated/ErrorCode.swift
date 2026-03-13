// Auto-generated from octomil-contracts. Do not edit.

public enum ErrorCode: String, Codable, Sendable {
    case invalidApiKey = "invalid_api_key"
    case authenticationFailed = "authentication_failed"
    case forbidden = "forbidden"
    case deviceNotRegistered = "device_not_registered"
    case tokenExpired = "token_expired"
    case deviceRevoked = "device_revoked"
    case networkUnavailable = "network_unavailable"
    case requestTimeout = "request_timeout"
    case serverError = "server_error"
    case rateLimited = "rate_limited"
    case invalidInput = "invalid_input"
    case unsupportedModality = "unsupported_modality"
    case contextTooLarge = "context_too_large"
    case modelNotFound = "model_not_found"
    case modelDisabled = "model_disabled"
    case versionNotFound = "version_not_found"
    case downloadFailed = "download_failed"
    case checksumMismatch = "checksum_mismatch"
    case insufficientStorage = "insufficient_storage"
    case insufficientMemory = "insufficient_memory"
    case runtimeUnavailable = "runtime_unavailable"
    case acceleratorUnavailable = "accelerator_unavailable"
    case modelLoadFailed = "model_load_failed"
    case inferenceFailed = "inference_failed"
    case streamInterrupted = "stream_interrupted"
    case policyDenied = "policy_denied"
    case cloudFallbackDisallowed = "cloud_fallback_disallowed"
    case maxToolRoundsExceeded = "max_tool_rounds_exceeded"
    case trainingFailed = "training_failed"
    case trainingNotSupported = "training_not_supported"
    case weightUploadFailed = "weight_upload_failed"
    case controlSyncFailed = "control_sync_failed"
    case assignmentNotFound = "assignment_not_found"
    case cancelled = "cancelled"
    case appBackgrounded = "app_backgrounded"
    case unknown = "unknown"
}

public enum ErrorCategory: String, Codable, Sendable {
    case auth = "auth"
    case network = "network"
    case input = "input"
    case catalog = "catalog"
    case download = "download"
    case device = "device"
    case runtime = "runtime"
    case policy = "policy"
    case training = "training"
    case control = "control"
    case lifecycle = "lifecycle"
    case unknown = "unknown"
}

public enum RetryClass: String, Codable, Sendable {
    case never = "never"
    case immediateSafe = "immediate_safe"
    case backoffSafe = "backoff_safe"
    case conditional = "conditional"
}

public enum SuggestedAction: String, Codable, Sendable {
    case fixCredentials = "fix_credentials"
    case reauthenticate = "reauthenticate"
    case checkPermissions = "check_permissions"
    case registerDevice = "register_device"
    case retryOrFallback = "retry_or_fallback"
    case retry = "retry"
    case retryAfter = "retry_after"
    case fixRequest = "fix_request"
    case reduceInputOrFallback = "reduce_input_or_fallback"
    case checkModelId = "check_model_id"
    case useAlternateModel = "use_alternate_model"
    case checkVersion = "check_version"
    case redownload = "redownload"
    case freeStorageOrFallback = "free_storage_or_fallback"
    case trySmallerModel = "try_smaller_model"
    case tryAlternateRuntime = "try_alternate_runtime"
    case tryCpuOrFallback = "try_cpu_or_fallback"
    case checkPolicy = "check_policy"
    case changePolicyOrFixLocal = "change_policy_or_fix_local"
    case increaseLimitOrSimplify = "increase_limit_or_simplify"
    case checkAssignment = "check_assignment"
    case none = "none"
    case resumeOnForeground = "resume_on_foreground"
    case reportBug = "report_bug"
}

extension ErrorCode {
    public var category: ErrorCategory {
        switch self {
        case .invalidApiKey: return .auth
        case .authenticationFailed: return .auth
        case .forbidden: return .auth
        case .deviceNotRegistered: return .auth
        case .tokenExpired: return .auth
        case .deviceRevoked: return .auth
        case .networkUnavailable: return .network
        case .requestTimeout: return .network
        case .serverError: return .network
        case .rateLimited: return .network
        case .invalidInput: return .input
        case .unsupportedModality: return .input
        case .contextTooLarge: return .input
        case .modelNotFound: return .catalog
        case .modelDisabled: return .catalog
        case .versionNotFound: return .catalog
        case .downloadFailed: return .download
        case .checksumMismatch: return .download
        case .insufficientStorage: return .device
        case .insufficientMemory: return .device
        case .runtimeUnavailable: return .device
        case .acceleratorUnavailable: return .device
        case .modelLoadFailed: return .runtime
        case .inferenceFailed: return .runtime
        case .streamInterrupted: return .runtime
        case .policyDenied: return .policy
        case .cloudFallbackDisallowed: return .policy
        case .maxToolRoundsExceeded: return .policy
        case .trainingFailed: return .training
        case .trainingNotSupported: return .training
        case .weightUploadFailed: return .training
        case .controlSyncFailed: return .control
        case .assignmentNotFound: return .control
        case .cancelled: return .lifecycle
        case .appBackgrounded: return .lifecycle
        case .unknown: return .unknown
        }
    }

    public var retryClass: RetryClass {
        switch self {
        case .invalidApiKey: return .never
        case .authenticationFailed: return .never
        case .forbidden: return .never
        case .deviceNotRegistered: return .never
        case .tokenExpired: return .never
        case .deviceRevoked: return .never
        case .networkUnavailable: return .backoffSafe
        case .requestTimeout: return .conditional
        case .serverError: return .backoffSafe
        case .rateLimited: return .conditional
        case .invalidInput: return .never
        case .unsupportedModality: return .never
        case .contextTooLarge: return .never
        case .modelNotFound: return .never
        case .modelDisabled: return .never
        case .versionNotFound: return .never
        case .downloadFailed: return .backoffSafe
        case .checksumMismatch: return .conditional
        case .insufficientStorage: return .never
        case .insufficientMemory: return .never
        case .runtimeUnavailable: return .never
        case .acceleratorUnavailable: return .never
        case .modelLoadFailed: return .conditional
        case .inferenceFailed: return .conditional
        case .streamInterrupted: return .immediateSafe
        case .policyDenied: return .never
        case .cloudFallbackDisallowed: return .never
        case .maxToolRoundsExceeded: return .never
        case .trainingFailed: return .conditional
        case .trainingNotSupported: return .never
        case .weightUploadFailed: return .backoffSafe
        case .controlSyncFailed: return .backoffSafe
        case .assignmentNotFound: return .never
        case .cancelled: return .never
        case .appBackgrounded: return .conditional
        case .unknown: return .never
        }
    }

    public var fallbackEligible: Bool {
        switch self {
        case .invalidApiKey: return false
        case .authenticationFailed: return false
        case .forbidden: return false
        case .deviceNotRegistered: return false
        case .tokenExpired: return false
        case .deviceRevoked: return false
        case .networkUnavailable: return true
        case .requestTimeout: return true
        case .serverError: return true
        case .rateLimited: return false
        case .invalidInput: return false
        case .unsupportedModality: return false
        case .contextTooLarge: return true
        case .modelNotFound: return false
        case .modelDisabled: return true
        case .versionNotFound: return false
        case .downloadFailed: return true
        case .checksumMismatch: return false
        case .insufficientStorage: return true
        case .insufficientMemory: return true
        case .runtimeUnavailable: return true
        case .acceleratorUnavailable: return true
        case .modelLoadFailed: return true
        case .inferenceFailed: return true
        case .streamInterrupted: return true
        case .policyDenied: return false
        case .cloudFallbackDisallowed: return false
        case .maxToolRoundsExceeded: return false
        case .trainingFailed: return false
        case .trainingNotSupported: return false
        case .weightUploadFailed: return false
        case .controlSyncFailed: return false
        case .assignmentNotFound: return false
        case .cancelled: return false
        case .appBackgrounded: return false
        case .unknown: return false
        }
    }

    public var suggestedAction: SuggestedAction {
        switch self {
        case .invalidApiKey: return .fixCredentials
        case .authenticationFailed: return .reauthenticate
        case .forbidden: return .checkPermissions
        case .deviceNotRegistered: return .registerDevice
        case .tokenExpired: return .reauthenticate
        case .deviceRevoked: return .registerDevice
        case .networkUnavailable: return .retryOrFallback
        case .requestTimeout: return .retryOrFallback
        case .serverError: return .retry
        case .rateLimited: return .retryAfter
        case .invalidInput: return .fixRequest
        case .unsupportedModality: return .fixRequest
        case .contextTooLarge: return .reduceInputOrFallback
        case .modelNotFound: return .checkModelId
        case .modelDisabled: return .useAlternateModel
        case .versionNotFound: return .checkVersion
        case .downloadFailed: return .retryOrFallback
        case .checksumMismatch: return .redownload
        case .insufficientStorage: return .freeStorageOrFallback
        case .insufficientMemory: return .trySmallerModel
        case .runtimeUnavailable: return .tryAlternateRuntime
        case .acceleratorUnavailable: return .tryCpuOrFallback
        case .modelLoadFailed: return .retryOrFallback
        case .inferenceFailed: return .retryOrFallback
        case .streamInterrupted: return .retry
        case .policyDenied: return .checkPolicy
        case .cloudFallbackDisallowed: return .changePolicyOrFixLocal
        case .maxToolRoundsExceeded: return .increaseLimitOrSimplify
        case .trainingFailed: return .retry
        case .trainingNotSupported: return .fixRequest
        case .weightUploadFailed: return .retry
        case .controlSyncFailed: return .retry
        case .assignmentNotFound: return .checkAssignment
        case .cancelled: return .none
        case .appBackgrounded: return .resumeOnForeground
        case .unknown: return .reportBug
        }
    }
}

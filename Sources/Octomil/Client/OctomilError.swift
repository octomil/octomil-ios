import Foundation

/// Errors that can occur during Octomil SDK operations.
public enum OctomilError: LocalizedError, Sendable {

    // MARK: - Network Errors

    /// Network is not available.
    case networkUnavailable

    /// Request timed out.
    case requestTimeout

    /// Server returned an error response.
    case serverError(statusCode: Int, message: String)

    /// Failed to decode server response.
    case decodingError(underlying: String)

    /// Invalid URL or request configuration.
    case invalidRequest(reason: String)

    // MARK: - Authentication Errors

    /// API key is invalid or expired.
    case invalidAPIKey

    /// Device is not registered.
    case deviceNotRegistered

    /// Authentication failed.
    case authenticationFailed(reason: String)

    // MARK: - Model Errors

    /// Model with specified ID was not found.
    case modelNotFound(modelId: String)

    /// Model version was not found.
    case versionNotFound(modelId: String, version: String)

    /// Model download failed.
    case downloadFailed(reason: String)

    /// Checksum verification failed after download.
    case checksumMismatch

    /// Failed to compile CoreML model.
    case modelCompilationFailed(reason: String)

    /// Model format is not supported.
    case unsupportedModelFormat(format: String)

    // MARK: - Cache Errors

    /// Cache operation failed.
    case cacheError(reason: String)

    /// Insufficient storage space.
    case insufficientStorage

    // MARK: - Training Errors

    /// Training failed.
    case trainingFailed(reason: String)

    /// Model does not support on-device training.
    case trainingNotSupported

    /// Weight extraction failed.
    case weightExtractionFailed(reason: String)

    /// Weight upload failed.
    case uploadFailed(reason: String)

    // MARK: - Keychain Errors

    /// Keychain operation failed.
    case keychainError(status: OSStatus)

    // MARK: - Contract Error Codes (added for full parity)

    /// 403 — insufficient permissions.
    case forbidden(reason: String)

    /// Kill switch active for this model.
    case modelDisabled(modelId: String)

    /// No compatible runtime for this model format.
    case runtimeUnavailable(reason: String)

    /// Runtime initialization error (model failed to load).
    case modelLoadFailed(reason: String)

    /// Prediction error during inference.
    case inferenceFailed(reason: String)

    /// OOM during inference or model loading.
    case insufficientMemory(reason: String)

    /// 429 — too many requests.
    case rateLimited(retryAfter: String?)

    /// Bad input data (malformed, wrong type, out of range).
    case invalidInput(reason: String)

    // MARK: - General Errors

    /// An unexpected error occurred.
    case unknown(underlying: Error?)

    /// Operation was cancelled.
    case cancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network is not available. Please check your connection."
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decodingError(let underlying):
            return "Failed to decode response: \(underlying)"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .invalidAPIKey:
            return "API key is invalid or expired."
        case .deviceNotRegistered:
            return "Device is not registered. Please call register() first."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .modelNotFound(let modelId):
            return "Model not found: \(modelId)"
        case .versionNotFound(let modelId, let version):
            return "Version \(version) not found for model \(modelId)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .checksumMismatch:
            return "Downloaded model checksum does not match. File may be corrupted."
        case .modelCompilationFailed(let reason):
            return "Failed to compile CoreML model: \(reason)"
        case .unsupportedModelFormat(let format):
            return "Model format '\(format)' is not supported on iOS."
        case .cacheError(let reason):
            return "Cache error: \(reason)"
        case .insufficientStorage:
            return "Insufficient storage space for model."
        case .trainingFailed(let reason):
            return "Training failed: \(reason)"
        case .trainingNotSupported:
            return "This model does not support on-device training."
        case .weightExtractionFailed(let reason):
            return "Failed to extract model weights: \(reason)"
        case .uploadFailed(let reason):
            return "Failed to upload weights: \(reason)"
        case .keychainError(let status):
            return "Keychain error (status: \(status))"
        case .forbidden(let reason):
            return "Forbidden: \(reason)"
        case .modelDisabled(let modelId):
            return "Model '\(modelId)' is disabled."
        case .runtimeUnavailable(let reason):
            return "No compatible runtime: \(reason)"
        case .modelLoadFailed(let reason):
            return "Model load failed: \(reason)"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        case .insufficientMemory(let reason):
            return "Insufficient memory: \(reason)"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited. Retry after \(retryAfter)."
            }
            return "Rate limited. Try again later."
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .unknown(let underlying):
            if let error = underlying {
                return "An unexpected error occurred: \(error.localizedDescription)"
            }
            return "An unexpected error occurred."
        case .cancelled:
            return "Operation was cancelled."
        }
    }

    public var failureReason: String? {
        errorDescription
    }

    public var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Check your network connection and try again."
        case .requestTimeout:
            return "Ensure you have a stable connection and try again."
        case .serverError:
            return "Try again later. If the problem persists, contact support."
        case .invalidAPIKey:
            return "Verify your API key is correct and not expired."
        case .deviceNotRegistered:
            return "Call client.register() to register the device."
        case .checksumMismatch:
            return "Try downloading the model again."
        case .insufficientStorage:
            return "Free up storage space on the device."
        case .trainingNotSupported:
            return "Use a model that supports on-device training."
        case .forbidden:
            return "Check that your account has the required permissions."
        case .rateLimited:
            return "Wait and retry with exponential backoff."
        case .insufficientMemory:
            return "Close other apps to free memory, or use a smaller model."
        case .modelLoadFailed:
            return "Try re-downloading the model or use a different format."
        default:
            return nil
        }
    }

    // MARK: - Contract Error Code Mapping

    /// Maps this error to the canonical ``ErrorCode`` from the contract.
    ///
    /// Every ``OctomilError`` case maps to exactly one ``ErrorCode``.
    /// SDK-specific cases that have no direct contract counterpart
    /// (e.g. ``decodingError``, ``keychainError``) map to ``ErrorCode/unknown``.
    public var errorCode: ErrorCode {
        switch self {
        case .networkUnavailable:
            return .networkUnavailable
        case .requestTimeout:
            return .requestTimeout
        case .serverError:
            return .serverError
        case .invalidAPIKey:
            return .invalidApiKey
        case .authenticationFailed, .deviceNotRegistered:
            return .authenticationFailed
        case .forbidden:
            return .forbidden
        case .modelNotFound, .versionNotFound:
            return .modelNotFound
        case .modelDisabled:
            return .modelDisabled
        case .downloadFailed:
            return .downloadFailed
        case .checksumMismatch:
            return .checksumMismatch
        case .insufficientStorage:
            return .insufficientStorage
        case .runtimeUnavailable, .unsupportedModelFormat:
            return .runtimeUnavailable
        case .modelLoadFailed, .modelCompilationFailed:
            return .modelLoadFailed
        case .inferenceFailed:
            return .inferenceFailed
        case .insufficientMemory:
            return .insufficientMemory
        case .rateLimited:
            return .rateLimited
        case .invalidInput, .invalidRequest:
            return .invalidInput
        case .cancelled:
            return .cancelled
        case .unknown, .decodingError, .cacheError, .keychainError,
             .trainingFailed, .trainingNotSupported,
             .weightExtractionFailed, .uploadFailed:
            return .unknown
        }
    }

    /// Whether this error is retryable, per the contract spec.
    ///
    /// Matches the `retryable` field from `enums/error_code.yaml`.
    public var isRetryable: Bool {
        switch errorCode {
        case .networkUnavailable, .requestTimeout, .serverError,
             .downloadFailed, .checksumMismatch, .modelLoadFailed,
             .inferenceFailed, .rateLimited:
            return true
        case .invalidApiKey, .authenticationFailed, .forbidden,
             .modelNotFound, .modelDisabled, .insufficientStorage,
             .runtimeUnavailable, .insufficientMemory, .invalidInput,
             .cancelled, .unknown:
            return false
        }
    }

    /// Creates an ``OctomilError`` from an ``ErrorCode`` and a message string.
    ///
    /// Useful when deserializing server error responses that include a
    /// contract-defined error code.
    public static func from(errorCode: ErrorCode, message: String) -> OctomilError {
        switch errorCode {
        case .networkUnavailable:
            return .networkUnavailable
        case .requestTimeout:
            return .requestTimeout
        case .serverError:
            return .serverError(statusCode: 500, message: message)
        case .invalidApiKey:
            return .invalidAPIKey
        case .authenticationFailed:
            return .authenticationFailed(reason: message)
        case .forbidden:
            return .forbidden(reason: message)
        case .modelNotFound:
            return .modelNotFound(modelId: message)
        case .modelDisabled:
            return .modelDisabled(modelId: message)
        case .downloadFailed:
            return .downloadFailed(reason: message)
        case .checksumMismatch:
            return .checksumMismatch
        case .insufficientStorage:
            return .insufficientStorage
        case .runtimeUnavailable:
            return .runtimeUnavailable(reason: message)
        case .modelLoadFailed:
            return .modelLoadFailed(reason: message)
        case .inferenceFailed:
            return .inferenceFailed(reason: message)
        case .insufficientMemory:
            return .insufficientMemory(reason: message)
        case .rateLimited:
            return .rateLimited(retryAfter: nil)
        case .invalidInput:
            return .invalidInput(reason: message)
        case .cancelled:
            return .cancelled
        case .unknown:
            return .unknown(underlying: nil)
        }
    }
}

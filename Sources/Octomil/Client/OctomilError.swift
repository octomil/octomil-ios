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
    ///
    /// - Note: Maps to ``ErrorCode/unknown`` — no dedicated catalog code exists
    ///   for client-side decoding failures.
    case decodingError(underlying: String)

    /// Invalid URL or request configuration.
    ///
    /// - Note: Maps to ``ErrorCode/invalidInput`` — closest catalog equivalent
    ///   for a malformed request.
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
    ///
    /// - Note: Maps to ``ErrorCode/modelLoadFailed`` — compilation failure is
    ///   a load-phase error in the contract taxonomy.
    case modelCompilationFailed(reason: String)

    /// Model format is not supported.
    ///
    /// - Note: Maps to ``ErrorCode/runtimeUnavailable`` — an unsupported format
    ///   means no runtime can handle it.
    case unsupportedModelFormat(format: String)

    // MARK: - Cache Errors

    /// Cache operation failed.
    ///
    /// - Note: Maps to ``ErrorCode/unknown`` — too implementation-specific for
    ///   a canonical code.
    case cacheError(reason: String)

    /// Insufficient storage space.
    case insufficientStorage

    // MARK: - Training Errors

    /// Training failed.
    case trainingFailed(reason: String)

    /// Model does not support on-device training.
    case trainingNotSupported

    /// Weight extraction failed.
    ///
    /// - Note: Maps to ``ErrorCode/weightUploadFailed`` — extraction is the
    ///   pre-upload step in the same training-upload flow.
    case weightExtractionFailed(reason: String)

    /// Weight upload failed.
    case uploadFailed(reason: String)

    // MARK: - Keychain Errors

    /// Keychain operation failed.
    ///
    /// - Note: Maps to ``ErrorCode/unknown`` — platform keychain status codes
    ///   have no direct catalog counterpart.
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

    // MARK: - Input / Context Errors

    /// Input modality not supported by the model.
    case unsupportedModality(reason: String)

    /// Input context exceeds the model's maximum.
    case contextTooLarge(reason: String)

    // MARK: - Runtime / Accelerator Errors

    /// Required hardware accelerator is unavailable.
    case acceleratorUnavailable(reason: String)

    /// Streaming connection was interrupted mid-response.
    case streamInterrupted(reason: String)

    // MARK: - Policy Errors

    /// Operation denied by an organization policy.
    case policyDenied(reason: String)

    /// Cloud fallback is disallowed by policy.
    case cloudFallbackDisallowed(reason: String)

    /// Maximum tool rounds exceeded for this request.
    case maxToolRoundsExceeded(reason: String)

    // MARK: - Control Plane Errors

    /// Control plane sync failed.
    case controlSyncFailed(reason: String)

    /// Assignment not found for the requested resource.
    case assignmentNotFound(reason: String)

    // MARK: - Auth Lifecycle Errors

    /// Access token has expired and must be refreshed or reissued.
    case tokenExpired

    /// Device registration has been revoked by an administrator.
    case deviceRevoked

    // MARK: - General Errors

    /// An unexpected error occurred.
    case unknown(underlying: Error?)

    /// Operation was cancelled.
    case cancelled

    /// App was backgrounded during an active operation.
    case appBackgrounded

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
        case .unsupportedModality(let reason):
            return "Unsupported modality: \(reason)"
        case .contextTooLarge(let reason):
            return "Context too large: \(reason)"
        case .acceleratorUnavailable(let reason):
            return "Accelerator unavailable: \(reason)"
        case .streamInterrupted(let reason):
            return "Stream interrupted: \(reason)"
        case .policyDenied(let reason):
            return "Policy denied: \(reason)"
        case .cloudFallbackDisallowed(let reason):
            return "Cloud fallback disallowed: \(reason)"
        case .maxToolRoundsExceeded(let reason):
            return "Max tool rounds exceeded: \(reason)"
        case .controlSyncFailed(let reason):
            return "Control sync failed: \(reason)"
        case .assignmentNotFound(let reason):
            return "Assignment not found: \(reason)"
        case .tokenExpired:
            return "Access token has expired. Refresh or reissue the token."
        case .deviceRevoked:
            return "Device registration has been revoked by an administrator."
        case .unknown(let underlying):
            if let error = underlying {
                return "An unexpected error occurred: \(error.localizedDescription)"
            }
            return "An unexpected error occurred."
        case .cancelled:
            return "Operation was cancelled."
        case .appBackgrounded:
            return "Operation interrupted because the app was backgrounded."
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
        case .tokenExpired:
            return "Refresh or reissue the access token."
        case .deviceRevoked:
            return "Re-register the device with the server."
        case .contextTooLarge:
            return "Reduce input size or use a model with a larger context window."
        case .acceleratorUnavailable:
            return "Try CPU-only mode or fall back to cloud."
        case .streamInterrupted:
            return "Retry the request."
        case .policyDenied:
            return "Check your organization's policy settings."
        case .cloudFallbackDisallowed:
            return "Change the fallback policy or fix the local runtime issue."
        case .controlSyncFailed:
            return "Retry the operation."
        case .appBackgrounded:
            return "Bring the app to the foreground to resume."
        default:
            return nil
        }
    }

    // MARK: - Contract Error Code Mapping

    /// The canonical ``ErrorCode`` from the contract taxonomy.
    ///
    /// Every ``OctomilError`` case maps to exactly one ``ErrorCode``.
    /// SDK-specific cases that have no direct contract counterpart
    /// (e.g. ``decodingError``, ``keychainError``) map to ``ErrorCode/unknown``.
    public var code: ErrorCode {
        switch self {
        case .networkUnavailable:
            return .networkUnavailable
        case .requestTimeout:
            return .requestTimeout
        case .serverError:
            return .serverError
        case .invalidAPIKey:
            return .invalidApiKey
        case .authenticationFailed:
            return .authenticationFailed
        case .deviceNotRegistered:
            return .deviceNotRegistered
        case .forbidden:
            return .forbidden
        case .modelNotFound:
            return .modelNotFound
        case .versionNotFound:
            return .versionNotFound
        case .modelDisabled:
            return .modelDisabled
        case .downloadFailed:
            return .downloadFailed
        case .checksumMismatch:
            return .checksumMismatch
        case .insufficientStorage:
            return .insufficientStorage
        case .runtimeUnavailable, .unsupportedModelFormat:
            // unsupportedModelFormat: no runtime can handle the format
            return .runtimeUnavailable
        case .modelLoadFailed, .modelCompilationFailed:
            // modelCompilationFailed: compilation is a load-phase error
            return .modelLoadFailed
        case .inferenceFailed:
            return .inferenceFailed
        case .insufficientMemory:
            return .insufficientMemory
        case .rateLimited:
            return .rateLimited
        case .invalidInput, .invalidRequest:
            // invalidRequest: malformed URL/config is closest to invalidInput
            return .invalidInput
        case .unsupportedModality:
            return .unsupportedModality
        case .contextTooLarge:
            return .contextTooLarge
        case .acceleratorUnavailable:
            return .acceleratorUnavailable
        case .streamInterrupted:
            return .streamInterrupted
        case .policyDenied:
            return .policyDenied
        case .cloudFallbackDisallowed:
            return .cloudFallbackDisallowed
        case .maxToolRoundsExceeded:
            return .maxToolRoundsExceeded
        case .controlSyncFailed:
            return .controlSyncFailed
        case .assignmentNotFound:
            return .assignmentNotFound
        case .cancelled:
            return .cancelled
        case .appBackgrounded:
            return .appBackgrounded
        case .tokenExpired:
            return .tokenExpired
        case .deviceRevoked:
            return .deviceRevoked
        case .trainingFailed:
            return .trainingFailed
        case .trainingNotSupported:
            return .trainingNotSupported
        case .uploadFailed, .weightExtractionFailed:
            // weightExtractionFailed: extraction is the pre-upload step
            return .weightUploadFailed
        // SDK-specific cases with no direct contract counterpart:
        // cacheError and keychainError are too implementation-specific.
        // decodingError is a client-side transport concern.
        case .unknown, .decodingError, .cacheError, .keychainError:
            return .unknown
        }
    }

    /// Maps this error to the canonical ``ErrorCode`` from the contract.
    ///
    /// - Note: Prefer ``code`` over this property. This alias is preserved
    ///   for source compatibility with existing call sites.
    public var errorCode: ErrorCode { code }

    /// Whether this error is retryable, per the contract spec.
    ///
    /// Delegates to ``ErrorCode/retryClass`` — `.never` means not retryable.
    public var retryable: Bool {
        code.retryClass != .never
    }

    /// Whether this error is retryable, per the contract spec.
    ///
    /// - Note: Prefer ``retryable`` over this property. This alias is preserved
    ///   for source compatibility with existing call sites.
    public var isRetryable: Bool { retryable }

    /// The error category from the contract taxonomy.
    public var category: ErrorCategory {
        code.category
    }

    /// The retry classification from the contract taxonomy.
    public var retryClass: RetryClass {
        code.retryClass
    }

    /// Whether this error is eligible for cloud fallback.
    public var fallbackEligible: Bool {
        code.fallbackEligible
    }

    /// The suggested remediation action from the contract taxonomy.
    public var suggestedAction: SuggestedAction {
        code.suggestedAction
    }

    /// Milliseconds the caller should wait before retrying, when available.
    ///
    /// Populated by the HTTP layer from the `Retry-After` response header.
    /// `nil` means no server-specified delay — use your own backoff strategy.
    ///
    /// Accepts bare integers (`"30"`) or values with a trailing `s` suffix
    /// (`"30s"`) as seconds. HTTP-date strings are not parsed and return `nil`.
    public var retryAfterMs: Int64? {
        switch self {
        case .rateLimited(let retryAfter):
            guard let raw = retryAfter else { return nil }
            // Strip optional "s" suffix (produced by the from(code:message:retryAfterMs:) factory)
            // then parse as integer seconds. HTTP-date strings won't parse and return nil.
            let stripped = raw.trimmingCharacters(in: .whitespaces)
                              .hasSuffix("s")
                ? String(raw.trimmingCharacters(in: .whitespaces).dropLast())
                : raw.trimmingCharacters(in: .whitespaces)
            if let seconds = Int64(stripped) {
                return seconds * 1_000
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Factory

    /// Creates an ``OctomilError`` from a catalog error code, a descriptive
    /// message, and an optional retry delay parsed from the `Retry-After`
    /// HTTP header.
    ///
    /// This is the preferred construction path when deserializing error
    /// responses from the Octomil API.
    ///
    /// ```swift
    /// let error = OctomilError.from(
    ///     code: .rateLimited,
    ///     message: "Too many requests",
    ///     retryAfterMs: 30_000
    /// )
    /// ```
    public static func from(code errorCode: ErrorCode, message: String, retryAfterMs: Int64? = nil) -> OctomilError {
        switch errorCode {
        case .networkUnavailable:
            return .networkUnavailable
        case .requestTimeout:
            return .requestTimeout
        case .serverError:
            return .serverError(statusCode: 500, message: message)
        case .invalidApiKey, .apiKeyNotFound, .apiKeyAlreadyRevoked:
            // apiKeyNotFound/apiKeyAlreadyRevoked: no dedicated OctomilError case;
            // closest is invalidAPIKey (auth failure at key level).
            return .invalidAPIKey
        case .authenticationFailed, .passkeyChallengeExpired, .passkeyCredentialNotFound,
             .invalidToken, .emailAlreadyVerified, .emailAlreadyInUse, .lastAuthMethod,
             .oauthProviderNotLinked, .credentialNotFound:
            return .authenticationFailed(reason: message)
        case .forbidden:
            return .forbidden(reason: message)
        case .insufficientScope, .missingOrgContext:
            // insufficientScope/missingOrgContext: permission-level auth errors;
            // map to forbidden as the closest user-facing case.
            return .forbidden(reason: message)
        case .deviceNotRegistered:
            return .deviceNotRegistered
        case .tokenExpired:
            return .tokenExpired
        case .deviceRevoked:
            return .deviceRevoked
        case .cloudCredentialsMissing:
            return .authenticationFailed(reason: message)
        case .cloudCredentialsRevoked:
            return .authenticationFailed(reason: message)
        case .cloudProviderAuthFailed:
            return .authenticationFailed(reason: message)
        case .rateLimited:
            // Convert retryAfterMs back to a string for the retryAfter field.
            let retryAfterStr: String? = retryAfterMs.map { "\($0 / 1_000)s" }
            return .rateLimited(retryAfter: retryAfterStr)
        case .invalidInput:
            return .invalidInput(reason: message)
        case .unsupportedModality:
            return .unsupportedModality(reason: message)
        case .contextTooLarge:
            return .contextTooLarge(reason: message)
        case .modelNotFound:
            return .modelNotFound(modelId: message)
        case .noDefaultModel:
            // noDefaultModel: no dedicated OctomilError case; closest is
            // modelNotFound since no model is resolvable.
            return .modelNotFound(modelId: message)
        case .capabilityNotSupported, .capabilityNotConfigured:
            // No dedicated OctomilError case; unsupportedModelFormat is the
            // closest iOS-specific surface (feature not available on this model).
            return .unsupportedModelFormat(format: message)
        case .previousResponseNotFound, .appNotFound, .appContextConflict,
             .invalidModelRef, .integrationNotFound, .actionNotFound,
             .actionStateInvalid, .billingCustomerNotFound:
            // Catalog/resource lookup failures with no direct OctomilError case;
            // map to invalidRequest as a general "bad reference" bucket.
            return .invalidRequest(reason: message)
        case .modelDisabled:
            return .modelDisabled(modelId: message)
        case .versionNotFound:
            return .versionNotFound(modelId: "", version: message)
        case .downloadFailed:
            return .downloadFailed(reason: message)
        case .checksumMismatch:
            return .checksumMismatch
        case .insufficientStorage:
            return .insufficientStorage
        case .insufficientMemory:
            return .insufficientMemory(reason: message)
        case .runtimeUnavailable:
            return .runtimeUnavailable(reason: message)
        case .localRuntimeNotFound:
            return .runtimeUnavailable(reason: message)
        case .acceleratorUnavailable:
            return .acceleratorUnavailable(reason: message)
        case .modelLoadFailed:
            return .modelLoadFailed(reason: message)
        case .inferenceFailed:
            return .inferenceFailed(reason: message)
        case .providerError, .upstreamProviderError:
            // No dedicated OctomilError case; inference failure is the closest
            // runtime-layer error visible to callers.
            return .inferenceFailed(reason: message)
        case .upstreamProviderUnavailable, .agentSystemUnavailable:
            // Transient upstream/platform outages are server-side availability errors.
            return .serverError(statusCode: 503, message: message)
        case .tooManyTools, .unsupportedToolCalling:
            // Tool-calling policy errors; map to invalidRequest (caller must fix
            // the tool configuration).
            return .invalidRequest(reason: message)
        case .streamInterrupted:
            return .streamInterrupted(reason: message)
        case .policyDenied:
            return .policyDenied(reason: message)
        case .cloudFallbackDisallowed:
            return .cloudFallbackDisallowed(reason: message)
        case .cloudInferenceNotAllowed, .hostedTtsDisabled:
            // Policy-level disablement; cloudFallbackDisallowed is the closest
            // existing OctomilError case for cloud policy enforcement.
            return .cloudFallbackDisallowed(reason: message)
        case .planLimitExceeded:
            // Billing plan ceiling hit; rateLimited is the closest surface
            // (caller must upgrade or wait for limit reset).
            return .rateLimited(retryAfter: nil)
        case .maxToolRoundsExceeded:
            return .maxToolRoundsExceeded(reason: message)
        case .controlSyncFailed:
            return .controlSyncFailed(reason: message)
        case .assignmentNotFound:
            return .assignmentNotFound(reason: message)
        case .incidentNotFound, .alertRuleNotFound, .deploymentNotFound, .experimentNotFound,
             .experimentStateInvalid, .threadNotFound, .runNotFound, .runStateInvalid,
             .approvalNotFound, .approvalAlreadyResolved, .jobNotFound, .jobStateInvalid:
            // Control-plane resource not found; no dedicated OctomilError case;
            // map to assignmentNotFound as the closest control-plane lookup error.
            return .assignmentNotFound(reason: message)
        case .connectionNotFound, .checkoutNotComplete, .resourceNotFound,
             .catalogFamilyNotFound, .catalogVariantNotFound, .catalogVersionNotFound,
             .catalogPackageNotFound, .catalogResourceNotFound, .catalogSlugConflict,
             .catalogLifecycleInvalid, .billingExportNotFound, .cloudCatalogSourceNotFound,
             .cloudCatalogMappingNotFound, .cloudCatalogRunNotFound, .conflict, .gone,
             .payloadTooLarge:
            // Catalog and lifecycle lookup failures do not have dedicated public
            // cases; invalidRequest is the SDK's catch-all for bad references or
            // request state.
            return .invalidRequest(reason: message)
        case .trainingFailed:
            return .trainingFailed(reason: message)
        case .trainingNotSupported:
            return .trainingNotSupported
        case .weightUploadFailed:
            return .uploadFailed(reason: message)
        case .cancelled:
            return .cancelled
        case .appBackgrounded:
            return .appBackgrounded
        case .unknown:
            return .unknown(underlying: nil)
        }
    }

    /// Creates an ``OctomilError`` from an ``ErrorCode`` and a message string.
    ///
    /// - Important: Deprecated. Use ``from(code:message:retryAfterMs:)`` instead.
    @available(*, deprecated, renamed: "from(code:message:retryAfterMs:)")
    public static func from(errorCode: ErrorCode, message: String) -> OctomilError {
        from(code: errorCode, message: message, retryAfterMs: nil)
    }

    // MARK: - API error-payload bridge

    /// Creates an ``OctomilError`` from a decoded API error payload.
    ///
    /// This overload bridges the hand-owned `_OctomilAPIErrorPayload` type
    /// (see `APIErrorPayload.swift`) to the SDK's public error surface.
    ///
    /// ```swift
    /// // When the server returns a structured error body:
    /// let payload = _OctomilAPIErrorPayload(code: "model_not_found", message: "llama-3")
    /// let error = OctomilError.from(apiPayload: payload)
    /// // -> OctomilError.modelNotFound(modelId: "llama-3")
    /// ```
    ///
    /// - Parameter apiPayload: A generated error payload decoded from the API response.
    /// - Returns: The corresponding ``OctomilError``.
    internal static func from(apiPayload: _OctomilAPIErrorPayload) -> OctomilError {
        let code = ErrorCode(rawValue: apiPayload.code) ?? .unknown
        return from(code: code, message: apiPayload.message, retryAfterMs: apiPayload.retry_after_ms)
    }
}

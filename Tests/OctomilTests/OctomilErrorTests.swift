import XCTest
@testable import Octomil

final class OctomilErrorTests: XCTestCase {

    // MARK: - Error Description Tests

    func testNetworkErrors() {
        XCTAssertNotNil(OctomilError.networkUnavailable.errorDescription)
        XCTAssertTrue(OctomilError.networkUnavailable.errorDescription!.contains("Network"))

        XCTAssertNotNil(OctomilError.requestTimeout.errorDescription)
        XCTAssertTrue(OctomilError.requestTimeout.errorDescription!.contains("timed out"))
    }

    func testServerErrors() {
        let error = OctomilError.serverError(statusCode: 500, message: "Internal Server Error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("500"))
        XCTAssertTrue(error.errorDescription!.contains("Internal Server Error"))
    }

    func testAuthenticationErrors() {
        XCTAssertNotNil(OctomilError.invalidAPIKey.errorDescription)
        XCTAssertTrue(OctomilError.invalidAPIKey.errorDescription!.contains("API key"))

        XCTAssertNotNil(OctomilError.deviceNotRegistered.errorDescription)
        XCTAssertTrue(OctomilError.deviceNotRegistered.errorDescription!.contains("registered"))

        let authError = OctomilError.authenticationFailed(reason: "Token expired")
        XCTAssertTrue(authError.errorDescription!.contains("Token expired"))
    }

    func testModelErrors() {
        let notFoundError = OctomilError.modelNotFound(modelId: "test-model")
        XCTAssertTrue(notFoundError.errorDescription!.contains("test-model"))

        let versionError = OctomilError.versionNotFound(modelId: "test-model", version: "1.0.0")
        XCTAssertTrue(versionError.errorDescription!.contains("1.0.0"))
        XCTAssertTrue(versionError.errorDescription!.contains("test-model"))

        XCTAssertNotNil(OctomilError.checksumMismatch.errorDescription)
        XCTAssertTrue(OctomilError.checksumMismatch.errorDescription!.contains("checksum"))

        let compilationError = OctomilError.modelCompilationFailed(reason: "Invalid format")
        XCTAssertTrue(compilationError.errorDescription!.contains("Invalid format"))

        let formatError = OctomilError.unsupportedModelFormat(format: "custom")
        XCTAssertTrue(formatError.errorDescription!.contains("custom"))
    }

    func testTrainingErrors() {
        let trainingError = OctomilError.trainingFailed(reason: "Out of memory")
        XCTAssertTrue(trainingError.errorDescription!.contains("Out of memory"))

        XCTAssertNotNil(OctomilError.trainingNotSupported.errorDescription)
        XCTAssertTrue(OctomilError.trainingNotSupported.errorDescription!.contains("training"))

        let weightError = OctomilError.weightExtractionFailed(reason: "Invalid layer")
        XCTAssertTrue(weightError.errorDescription!.contains("Invalid layer"))

        let uploadError = OctomilError.uploadFailed(reason: "Network error")
        XCTAssertTrue(uploadError.errorDescription!.contains("Network error"))
    }

    func testCacheErrors() {
        let cacheError = OctomilError.cacheError(reason: "Disk full")
        XCTAssertTrue(cacheError.errorDescription!.contains("Disk full"))

        XCTAssertNotNil(OctomilError.insufficientStorage.errorDescription)
        XCTAssertTrue(OctomilError.insufficientStorage.errorDescription!.contains("storage"))
    }

    func testKeychainErrors() {
        let keychainError = OctomilError.keychainError(status: -25300)
        XCTAssertNotNil(keychainError.errorDescription)
        XCTAssertTrue(keychainError.errorDescription!.contains("-25300"))
    }

    func testGeneralErrors() {
        let unknownError = OctomilError.unknown(underlying: NSError(domain: "test", code: 1))
        XCTAssertNotNil(unknownError.errorDescription)

        let unknownNilError = OctomilError.unknown(underlying: nil)
        XCTAssertNotNil(unknownNilError.errorDescription)

        XCTAssertNotNil(OctomilError.cancelled.errorDescription)
        XCTAssertTrue(OctomilError.cancelled.errorDescription!.contains("cancelled"))
    }

    // MARK: - Contract Error Code Tests

    func testContractErrorCodeDescriptions() {
        let forbidden = OctomilError.forbidden(reason: "insufficient permissions")
        XCTAssertNotNil(forbidden.errorDescription)
        XCTAssertTrue(forbidden.errorDescription!.contains("Forbidden"))

        let modelDisabled = OctomilError.modelDisabled(modelId: "test-model")
        XCTAssertNotNil(modelDisabled.errorDescription)
        XCTAssertTrue(modelDisabled.errorDescription!.contains("disabled"))

        let runtimeUnavailable = OctomilError.runtimeUnavailable(reason: "no CoreML support")
        XCTAssertNotNil(runtimeUnavailable.errorDescription)
        XCTAssertTrue(runtimeUnavailable.errorDescription!.contains("runtime"))

        let modelLoadFailed = OctomilError.modelLoadFailed(reason: "corrupt weights")
        XCTAssertNotNil(modelLoadFailed.errorDescription)
        XCTAssertTrue(modelLoadFailed.errorDescription!.contains("load failed"))

        let inferenceFailed = OctomilError.inferenceFailed(reason: "shape mismatch")
        XCTAssertNotNil(inferenceFailed.errorDescription)
        XCTAssertTrue(inferenceFailed.errorDescription!.contains("Inference"))

        let insufficientMemory = OctomilError.insufficientMemory(reason: "OOM")
        XCTAssertNotNil(insufficientMemory.errorDescription)
        XCTAssertTrue(insufficientMemory.errorDescription!.contains("memory"))

        let rateLimited = OctomilError.rateLimited(retryAfter: "30s")
        XCTAssertNotNil(rateLimited.errorDescription)
        XCTAssertTrue(rateLimited.errorDescription!.contains("Rate limited"))

        let rateLimitedNoRetry = OctomilError.rateLimited(retryAfter: nil)
        XCTAssertTrue(rateLimitedNoRetry.errorDescription!.contains("later"))

        let invalidInput = OctomilError.invalidInput(reason: "empty prompt")
        XCTAssertNotNil(invalidInput.errorDescription)
        XCTAssertTrue(invalidInput.errorDescription!.contains("Invalid input"))
    }

    // MARK: - Recovery Suggestion Tests

    func testRecoverySuggestions() {
        XCTAssertNotNil(OctomilError.networkUnavailable.recoverySuggestion)
        XCTAssertNotNil(OctomilError.requestTimeout.recoverySuggestion)
        XCTAssertNotNil(OctomilError.invalidAPIKey.recoverySuggestion)
        XCTAssertNotNil(OctomilError.deviceNotRegistered.recoverySuggestion)
        XCTAssertNotNil(OctomilError.checksumMismatch.recoverySuggestion)
        XCTAssertNotNil(OctomilError.insufficientStorage.recoverySuggestion)
        XCTAssertNotNil(OctomilError.trainingNotSupported.recoverySuggestion)
        XCTAssertNotNil(OctomilError.forbidden(reason: "test").recoverySuggestion)
        XCTAssertNotNil(OctomilError.rateLimited(retryAfter: nil).recoverySuggestion)
        XCTAssertNotNil(OctomilError.insufficientMemory(reason: "test").recoverySuggestion)
        XCTAssertNotNil(OctomilError.modelLoadFailed(reason: "test").recoverySuggestion)
    }

    // MARK: - .code property (canonical ErrorCode)

    func testCodePropertyMatchesExpectedCodes() {
        XCTAssertEqual(OctomilError.networkUnavailable.code, .networkUnavailable)
        XCTAssertEqual(OctomilError.requestTimeout.code, .requestTimeout)
        XCTAssertEqual(OctomilError.serverError(statusCode: 503, message: "").code, .serverError)
        XCTAssertEqual(OctomilError.invalidAPIKey.code, .invalidApiKey)
        XCTAssertEqual(OctomilError.authenticationFailed(reason: "").code, .authenticationFailed)
        XCTAssertEqual(OctomilError.deviceNotRegistered.code, .deviceNotRegistered)
        XCTAssertEqual(OctomilError.tokenExpired.code, .tokenExpired)
        XCTAssertEqual(OctomilError.deviceRevoked.code, .deviceRevoked)
        XCTAssertEqual(OctomilError.forbidden(reason: "").code, .forbidden)
        XCTAssertEqual(OctomilError.rateLimited(retryAfter: nil).code, .rateLimited)
        XCTAssertEqual(OctomilError.modelNotFound(modelId: "m").code, .modelNotFound)
        XCTAssertEqual(OctomilError.modelDisabled(modelId: "m").code, .modelDisabled)
        XCTAssertEqual(OctomilError.checksumMismatch.code, .checksumMismatch)
        XCTAssertEqual(OctomilError.insufficientStorage.code, .insufficientStorage)
        XCTAssertEqual(OctomilError.insufficientMemory(reason: "").code, .insufficientMemory)
        XCTAssertEqual(OctomilError.inferenceFailed(reason: "").code, .inferenceFailed)
        XCTAssertEqual(OctomilError.streamInterrupted(reason: "").code, .streamInterrupted)
        XCTAssertEqual(OctomilError.cancelled.code, .cancelled)
        XCTAssertEqual(OctomilError.appBackgrounded.code, .appBackgrounded)
    }

    func testCodePropertyForSDKSpecificCases() {
        // SDK-specific cases with no direct catalog code collapse to .unknown
        XCTAssertEqual(OctomilError.unknown(underlying: nil).code, .unknown)
        XCTAssertEqual(OctomilError.decodingError(underlying: "bad json").code, .unknown)
        XCTAssertEqual(OctomilError.cacheError(reason: "disk full").code, .unknown)
        XCTAssertEqual(OctomilError.keychainError(status: -25300).code, .unknown)

        // Multi-case mappings
        XCTAssertEqual(OctomilError.unsupportedModelFormat(format: "safetensors").code, .runtimeUnavailable)
        XCTAssertEqual(OctomilError.modelCompilationFailed(reason: "bad arch").code, .modelLoadFailed)
        XCTAssertEqual(OctomilError.invalidRequest(reason: "bad url").code, .invalidInput)
        XCTAssertEqual(OctomilError.weightExtractionFailed(reason: "layer missing").code, .weightUploadFailed)
        XCTAssertEqual(OctomilError.uploadFailed(reason: "timeout").code, .weightUploadFailed)
    }

    func testErrorCodeAliasMatchesCode() {
        // errorCode is preserved as a back-compat alias; must equal code
        let errors: [OctomilError] = [
            .networkUnavailable,
            .invalidAPIKey,
            .modelNotFound(modelId: "x"),
            .inferenceFailed(reason: "oops"),
            .unknown(underlying: nil),
        ]
        for error in errors {
            XCTAssertEqual(error.code, error.errorCode,
                           "errorCode alias must equal code for \(error)")
        }
    }

    // MARK: - .retryable property

    func testRetryableForNonRetryableErrors() {
        XCTAssertFalse(OctomilError.invalidAPIKey.retryable)
        XCTAssertFalse(OctomilError.forbidden(reason: "").retryable)
        XCTAssertFalse(OctomilError.modelNotFound(modelId: "x").retryable)
        XCTAssertFalse(OctomilError.trainingNotSupported.retryable)
        XCTAssertFalse(OctomilError.cancelled.retryable)
        XCTAssertFalse(OctomilError.insufficientStorage.retryable)
    }

    func testRetryableForRetryableErrors() {
        XCTAssertTrue(OctomilError.networkUnavailable.retryable)
        XCTAssertTrue(OctomilError.serverError(statusCode: 503, message: "").retryable)
        XCTAssertTrue(OctomilError.downloadFailed(reason: "timeout").retryable)
        XCTAssertTrue(OctomilError.streamInterrupted(reason: "reset").retryable)
        XCTAssertTrue(OctomilError.trainingFailed(reason: "oom").retryable)
    }

    func testIsRetryableAliasMatchesRetryable() {
        let errors: [OctomilError] = [
            .networkUnavailable,
            .invalidAPIKey,
            .rateLimited(retryAfter: "5"),
            .cancelled,
        ]
        for error in errors {
            XCTAssertEqual(error.retryable, error.isRetryable,
                           "isRetryable alias must equal retryable for \(error)")
        }
    }

    // MARK: - .suggestedAction property

    func testSuggestedActionDelegatesToCode() {
        XCTAssertEqual(OctomilError.invalidAPIKey.suggestedAction, .fixCredentials)
        XCTAssertEqual(OctomilError.deviceNotRegistered.suggestedAction, .registerDevice)
        XCTAssertEqual(OctomilError.rateLimited(retryAfter: nil).suggestedAction, .retryAfter)
        XCTAssertEqual(OctomilError.networkUnavailable.suggestedAction, .retryOrFallback)
        XCTAssertEqual(OctomilError.insufficientStorage.suggestedAction, .freeStorageOrFallback)
        XCTAssertEqual(OctomilError.insufficientMemory(reason: "").suggestedAction, .trySmallerModel)
        XCTAssertEqual(OctomilError.acceleratorUnavailable(reason: "").suggestedAction, .tryCpuOrFallback)
        XCTAssertEqual(OctomilError.checksumMismatch.suggestedAction, .redownload)
        XCTAssertEqual(OctomilError.cancelled.suggestedAction, .none)
        XCTAssertEqual(OctomilError.appBackgrounded.suggestedAction, .resumeOnForeground)
        XCTAssertEqual(OctomilError.unknown(underlying: nil).suggestedAction, .reportBug)
    }

    // MARK: - .retryAfterMs property

    func testRetryAfterMsIsNilForNonRateLimitedErrors() {
        XCTAssertNil(OctomilError.networkUnavailable.retryAfterMs)
        XCTAssertNil(OctomilError.serverError(statusCode: 500, message: "").retryAfterMs)
        XCTAssertNil(OctomilError.invalidAPIKey.retryAfterMs)
        XCTAssertNil(OctomilError.rateLimited(retryAfter: nil).retryAfterMs)
    }

    func testRetryAfterMsConvertsSecondsToMilliseconds() {
        // "30" seconds -> 30_000 ms
        let error = OctomilError.rateLimited(retryAfter: "30")
        XCTAssertEqual(error.retryAfterMs, 30_000)
    }

    func testRetryAfterMsWithTrailingWhitespace() {
        let error = OctomilError.rateLimited(retryAfter: " 60 ")
        XCTAssertEqual(error.retryAfterMs, 60_000)
    }

    func testRetryAfterMsReturnsNilForHttpDateFormat() {
        // HTTP-date strings are not parsed; nil is expected
        let error = OctomilError.rateLimited(retryAfter: "Wed, 21 Oct 2025 07:28:00 GMT")
        XCTAssertNil(error.retryAfterMs)
    }

    // MARK: - from(code:message:retryAfterMs:) factory

    func testFromCodeFactoryBasicMapping() {
        let networkError = OctomilError.from(code: .networkUnavailable, message: "no network")
        if case .networkUnavailable = networkError { } else {
            XCTFail("Expected .networkUnavailable, got \(networkError)")
        }

        let authError = OctomilError.from(code: .invalidApiKey, message: "bad key")
        if case .invalidAPIKey = authError { } else {
            XCTFail("Expected .invalidAPIKey, got \(authError)")
        }

        let modelError = OctomilError.from(code: .modelNotFound, message: "llama-3")
        if case .modelNotFound(let id) = modelError {
            XCTAssertEqual(id, "llama-3")
        } else {
            XCTFail("Expected .modelNotFound, got \(modelError)")
        }
    }

    func testFromCodeFactoryRetryAfterMsRoundTrip() {
        // rateLimited with retryAfterMs should produce a retryAfter string
        let error = OctomilError.from(code: .rateLimited, message: "slow down", retryAfterMs: 30_000)
        if case .rateLimited(let retryAfter) = error {
            XCTAssertEqual(retryAfter, "30s")
        } else {
            XCTFail("Expected .rateLimited, got \(error)")
        }
        // Round-trip: retryAfterMs should recover 30_000
        XCTAssertEqual(error.retryAfterMs, 30_000)
    }

    func testFromCodeFactoryRetryAfterMsNil() {
        let error = OctomilError.from(code: .rateLimited, message: "slow down", retryAfterMs: nil)
        if case .rateLimited(let retryAfter) = error {
            XCTAssertNil(retryAfter)
        } else {
            XCTFail("Expected .rateLimited, got \(error)")
        }
    }

    func testFromCodeFactoryNewCatalogCodes() {
        // insufficientScope -> .forbidden
        let scopeError = OctomilError.from(code: .insufficientScope, message: "missing write:models")
        if case .forbidden(let reason) = scopeError {
            XCTAssertEqual(reason, "missing write:models")
        } else {
            XCTFail("Expected .forbidden, got \(scopeError)")
        }

        // missingOrgContext -> .forbidden
        let orgError = OctomilError.from(code: .missingOrgContext, message: "no org")
        if case .forbidden = orgError { } else {
            XCTFail("Expected .forbidden, got \(orgError)")
        }

        // noDefaultModel -> .modelNotFound
        let noDefault = OctomilError.from(code: .noDefaultModel, message: "no-default")
        if case .modelNotFound = noDefault { } else {
            XCTFail("Expected .modelNotFound, got \(noDefault)")
        }

        // providerError -> .inferenceFailed
        let providerErr = OctomilError.from(code: .providerError, message: "upstream down")
        if case .inferenceFailed = providerErr { } else {
            XCTFail("Expected .inferenceFailed, got \(providerErr)")
        }

        // planLimitExceeded -> .rateLimited
        let planErr = OctomilError.from(code: .planLimitExceeded, message: "quota hit")
        if case .rateLimited = planErr { } else {
            XCTFail("Expected .rateLimited, got \(planErr)")
        }

        // cloudInferenceNotAllowed -> .cloudFallbackDisallowed
        let cloudErr = OctomilError.from(code: .cloudInferenceNotAllowed, message: "policy")
        if case .cloudFallbackDisallowed = cloudErr { } else {
            XCTFail("Expected .cloudFallbackDisallowed, got \(cloudErr)")
        }

        // experimentNotFound -> .assignmentNotFound
        let expErr = OctomilError.from(code: .experimentNotFound, message: "exp-123")
        if case .assignmentNotFound = expErr { } else {
            XCTFail("Expected .assignmentNotFound, got \(expErr)")
        }

        // apiKeyNotFound -> .invalidAPIKey
        let keyErr = OctomilError.from(code: .apiKeyNotFound, message: "key gone")
        if case .invalidAPIKey = keyErr { } else {
            XCTFail("Expected .invalidAPIKey, got \(keyErr)")
        }
    }

    func testFromCodeFactoryCodeRoundTrip() {
        // The .code property on errors constructed via the factory must equal the
        // input ErrorCode (for codes that have a 1:1 mapping).
        let directCodes: [ErrorCode] = [
            .networkUnavailable, .requestTimeout, .serverError,
            .authenticationFailed, .forbidden, .deviceNotRegistered,
            .tokenExpired, .deviceRevoked, .rateLimited,
            .invalidInput, .unsupportedModality, .contextTooLarge,
            .modelNotFound, .modelDisabled, .versionNotFound,
            .downloadFailed, .checksumMismatch, .insufficientStorage,
            .insufficientMemory, .runtimeUnavailable, .acceleratorUnavailable,
            .modelLoadFailed, .inferenceFailed, .streamInterrupted,
            .policyDenied, .cloudFallbackDisallowed, .maxToolRoundsExceeded,
            .controlSyncFailed, .assignmentNotFound,
            .trainingFailed, .trainingNotSupported, .weightUploadFailed,
            .cancelled, .appBackgrounded, .unknown,
        ]
        for errorCode in directCodes {
            let error = OctomilError.from(code: errorCode, message: "test", retryAfterMs: nil)
            XCTAssertEqual(error.code, errorCode,
                           "Round-trip failed for ErrorCode.\(errorCode)")
        }
    }

    // MARK: - Deprecated back-compat factory

    func testDeprecatedFromErrorCodeFactory() {
        // The deprecated overload must produce results identical to the new factory.
        let oldResult = OctomilError.from(errorCode: .inferenceFailed, message: "boom")
        let newResult = OctomilError.from(code: .inferenceFailed, message: "boom")
        XCTAssertEqual(oldResult.code, newResult.code)
    }
}

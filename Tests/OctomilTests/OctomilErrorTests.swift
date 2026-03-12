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
}

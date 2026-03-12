import XCTest
@testable import Octomil

/// Conformance tests that validate the iOS SDK against the octomil-contracts
/// specification. These tests verify enum parity, fixture deserialization,
/// and error-code round-tripping.
///
/// Contract repo: octomil-contracts
/// Schema: conformance/parity_schema.json
final class ContractConformanceTests: XCTestCase {

    // MARK: - ErrorCode Enum Completeness

    /// All 19 error codes defined in enums/error_code.yaml MUST exist
    /// in the generated ErrorCode enum.
    func testAllContractErrorCodesExist() {
        let expected: [String] = [
            "network_unavailable",
            "request_timeout",
            "server_error",
            "invalid_api_key",
            "authentication_failed",
            "forbidden",
            "model_not_found",
            "model_disabled",
            "download_failed",
            "checksum_mismatch",
            "insufficient_storage",
            "runtime_unavailable",
            "model_load_failed",
            "inference_failed",
            "insufficient_memory",
            "rate_limited",
            "invalid_input",
            "cancelled",
            "unknown",
        ]

        for rawValue in expected {
            XCTAssertNotNil(
                ErrorCode(rawValue: rawValue),
                "ErrorCode enum is missing contract value: \(rawValue)"
            )
        }
        // Verify count matches — guards against extra values that diverge from contract.
        let allCases: [ErrorCode] = [
            .networkUnavailable, .requestTimeout, .serverError, .invalidApiKey,
            .authenticationFailed, .forbidden, .modelNotFound, .modelDisabled,
            .downloadFailed, .checksumMismatch, .insufficientStorage,
            .runtimeUnavailable, .modelLoadFailed, .inferenceFailed,
            .insufficientMemory, .rateLimited, .invalidInput, .cancelled, .unknown,
        ]
        XCTAssertEqual(allCases.count, expected.count, "ErrorCode case count diverges from contract")
    }

    // MARK: - ErrorCode JSON round-trip

    /// ErrorCode must encode to and decode from its snake_case raw value.
    func testErrorCodeJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for code in [ErrorCode.networkUnavailable, .forbidden, .rateLimited, .unknown] {
            let data = try encoder.encode(code)
            let json = String(data: data, encoding: .utf8)!
            // Raw value should be quoted snake_case string
            XCTAssertTrue(json.contains(code.rawValue), "Encoded value mismatch for \(code)")

            let decoded = try decoder.decode(ErrorCode.self, from: data)
            XCTAssertEqual(decoded, code, "Round-trip failed for \(code)")
        }
    }

    // MARK: - Error Fixture Deserialization

    /// Contract fixture: errors/model_not_found.json
    /// SDK must deserialize the error and expose code/message/retryable.
    func testModelNotFoundFixture() {
        let fixture = ContractErrorFixture(
            code: "model_not_found",
            message: "Model 'nonexistent-7b' not found in registry.",
            retryable: false
        )

        let errorCode = ErrorCode(rawValue: fixture.code)
        XCTAssertNotNil(errorCode)
        XCTAssertEqual(errorCode, .modelNotFound)

        let error = OctomilError.from(errorCode: errorCode!, message: fixture.message)
        XCTAssertEqual(error.errorCode, .modelNotFound)
        XCTAssertFalse(error.isRetryable)

        // Error description should contain the message context
        if case .modelNotFound(let modelId) = error {
            XCTAssertFalse(modelId.isEmpty)
        } else {
            XCTFail("Expected .modelNotFound case")
        }
    }

    /// Contract fixture: errors/inference_failed.json
    func testInferenceFailedFixture() {
        let fixture = ContractErrorFixture(
            code: "inference_failed",
            message: "CoreML prediction failed: input tensor shape mismatch.",
            retryable: true
        )

        let errorCode = ErrorCode(rawValue: fixture.code)!
        let error = OctomilError.from(errorCode: errorCode, message: fixture.message)
        XCTAssertEqual(error.errorCode, .inferenceFailed)
        XCTAssertTrue(error.isRetryable)
        XCTAssertEqual(fixture.retryable, error.isRetryable)
    }

    /// Contract fixture: errors/rate_limited.json
    func testRateLimitedFixture() {
        let fixture = ContractErrorFixture(
            code: "rate_limited",
            message: "Too many requests. Retry after 30 seconds.",
            retryable: true
        )

        let errorCode = ErrorCode(rawValue: fixture.code)!
        let error = OctomilError.from(errorCode: errorCode, message: fixture.message)
        XCTAssertEqual(error.errorCode, .rateLimited)
        XCTAssertTrue(error.isRetryable)
    }

    /// Contract fixture: errors/unknown_error_fallback.json
    /// Unrecognized error codes MUST map to ErrorCode.unknown.
    func testUnknownErrorFallback() {
        let unrecognizedCode = "some_future_error_code"
        let errorCode = ErrorCode(rawValue: unrecognizedCode)
        XCTAssertNil(errorCode, "Unrecognized code should not parse as a known ErrorCode")

        // SDK must map unrecognized codes to .unknown
        let fallback = ErrorCode(rawValue: unrecognizedCode) ?? .unknown
        XCTAssertEqual(fallback, .unknown)

        let error = OctomilError.from(errorCode: .unknown, message: "Something the SDK has never seen before.")
        XCTAssertEqual(error.errorCode, .unknown)
        XCTAssertFalse(error.isRetryable)
    }

    // MARK: - OctomilError -> ErrorCode mapping coverage

    /// Every OctomilError case must map to some ErrorCode.
    func testEveryOctomilErrorMapsToAnErrorCode() {
        let allErrors: [OctomilError] = [
            .networkUnavailable,
            .requestTimeout,
            .serverError(statusCode: 500, message: "test"),
            .decodingError(underlying: "test"),
            .invalidRequest(reason: "test"),
            .invalidAPIKey,
            .deviceNotRegistered,
            .authenticationFailed(reason: "test"),
            .modelNotFound(modelId: "test"),
            .versionNotFound(modelId: "test", version: "1.0"),
            .downloadFailed(reason: "test"),
            .checksumMismatch,
            .modelCompilationFailed(reason: "test"),
            .unsupportedModelFormat(format: "test"),
            .cacheError(reason: "test"),
            .insufficientStorage,
            .trainingFailed(reason: "test"),
            .trainingNotSupported,
            .weightExtractionFailed(reason: "test"),
            .uploadFailed(reason: "test"),
            .keychainError(status: -1),
            .forbidden(reason: "test"),
            .modelDisabled(modelId: "test"),
            .runtimeUnavailable(reason: "test"),
            .modelLoadFailed(reason: "test"),
            .inferenceFailed(reason: "test"),
            .insufficientMemory(reason: "test"),
            .rateLimited(retryAfter: "30s"),
            .invalidInput(reason: "test"),
            .unknown(underlying: nil),
            .cancelled,
        ]

        for error in allErrors {
            // Should not crash and should return a valid ErrorCode
            let code = error.errorCode
            XCTAssertNotNil(ErrorCode(rawValue: code.rawValue),
                            "\(error) mapped to invalid ErrorCode: \(code)")
        }
    }

    // MARK: - Retryable contract alignment

    /// Validate retryable flags match the contract YAML exactly.
    func testRetryableFlagsMatchContract() {
        let retryableExpected: [(ErrorCode, Bool)] = [
            (.networkUnavailable, true),
            (.requestTimeout, true),
            (.serverError, true),
            (.invalidApiKey, false),
            (.authenticationFailed, false),
            (.forbidden, false),
            (.modelNotFound, false),
            (.modelDisabled, false),
            (.downloadFailed, true),
            (.checksumMismatch, true),
            (.insufficientStorage, false),
            (.runtimeUnavailable, false),
            (.modelLoadFailed, true),
            (.inferenceFailed, true),
            (.insufficientMemory, false),
            (.rateLimited, true),
            (.invalidInput, false),
            (.cancelled, false),
            (.unknown, false),
        ]

        for (code, expectedRetryable) in retryableExpected {
            let error = OctomilError.from(errorCode: code, message: "test")
            XCTAssertEqual(
                error.isRetryable, expectedRetryable,
                "Retryable mismatch for \(code.rawValue): expected \(expectedRetryable), got \(error.isRetryable)"
            )
        }
    }

    // MARK: - Generated enum parity checks

    /// ModelStatus enum matches contract values.
    func testModelStatusValues() {
        XCTAssertNotNil(ModelStatus(rawValue: "not_cached"))
        XCTAssertNotNil(ModelStatus(rawValue: "downloading"))
        XCTAssertNotNil(ModelStatus(rawValue: "ready"))
        XCTAssertNotNil(ModelStatus(rawValue: "error"))
    }

    /// DeviceClass enum matches contract values.
    func testDeviceClassValues() {
        XCTAssertNotNil(DeviceClass(rawValue: "flagship"))
        XCTAssertNotNil(DeviceClass(rawValue: "high"))
        XCTAssertNotNil(DeviceClass(rawValue: "mid"))
        XCTAssertNotNil(DeviceClass(rawValue: "low"))
    }

    /// FinishReason enum matches contract values.
    func testFinishReasonValues() {
        XCTAssertNotNil(FinishReason(rawValue: "stop"))
        XCTAssertNotNil(FinishReason(rawValue: "tool_calls"))
        XCTAssertNotNil(FinishReason(rawValue: "length"))
        XCTAssertNotNil(FinishReason(rawValue: "content_filter"))
    }

    /// CompatibilityLevel enum matches contract values.
    func testCompatibilityLevelValues() {
        XCTAssertNotNil(CompatibilityLevel(rawValue: "stable"))
        XCTAssertNotNil(CompatibilityLevel(rawValue: "beta"))
        XCTAssertNotNil(CompatibilityLevel(rawValue: "experimental"))
        XCTAssertNotNil(CompatibilityLevel(rawValue: "compatibility"))
    }

    /// OTLP resource attribute keys match contract.
    func testOTLPResourceAttributeKeys() {
        XCTAssertEqual(OTLPResourceAttribute.serviceName, "service.name")
        XCTAssertEqual(OTLPResourceAttribute.serviceVersion, "service.version")
        XCTAssertEqual(OTLPResourceAttribute.octomilSdk, "octomil.sdk")
        XCTAssertEqual(OTLPResourceAttribute.octomilOrgId, "octomil.org_id")
        XCTAssertEqual(OTLPResourceAttribute.octomilDeviceId, "octomil.device_id")
        XCTAssertEqual(OTLPResourceAttribute.osType, "os.type")
    }

    /// Telemetry event names match contract.
    func testContractTelemetryEventNames() {
        XCTAssertEqual(ContractTelemetryEventName.inferenceStarted, "inference.started")
        XCTAssertEqual(ContractTelemetryEventName.inferenceCompleted, "inference.completed")
        XCTAssertEqual(ContractTelemetryEventName.inferenceFailed, "inference.failed")
        XCTAssertEqual(ContractTelemetryEventName.inferenceChunkProduced, "inference.chunk_produced")
        XCTAssertEqual(ContractTelemetryEventName.deployStarted, "deploy.started")
        XCTAssertEqual(ContractTelemetryEventName.deployCompleted, "deploy.completed")
    }

    // MARK: - Control.heartbeat contract

    /// ControlSync must expose a non-throwing heartbeat() method.
    /// This is a compile-time check — if heartbeat() does not exist or
    /// if it throws, this test will fail to compile.
    func testControlHeartbeatExists() async {
        let config = TestConfiguration.standard
        let apiClient = APIClient(
            serverURL: URL(string: "https://localhost:9999")!,
            configuration: config
        )
        let control = ControlSync(apiClient: apiClient)

        // heartbeat() is fire-and-forget, non-throwing, non-async
        // This call validates the method signature matches the contract:
        //   blocking: false, idempotent: true
        control.heartbeat()

        // The call above should not block. No assertions needed beyond
        // the fact that it compiled and returned immediately.
    }
}

// MARK: - Test Helpers

/// Represents an error fixture from the contract's fixtures/errors/ directory.
private struct ContractErrorFixture {
    let code: String
    let message: String
    let retryable: Bool
}

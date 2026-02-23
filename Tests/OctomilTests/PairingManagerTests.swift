import Foundation
import XCTest
@testable import Octomil

/// Tests for ``PairingManager``, ``PairingModels``, and pairing API endpoints.
final class PairingManagerTests: XCTestCase {

    private static let testHost = "api.test.octomil.com"
    private static let testBaseURL = URL(string: "https://\(testHost)")!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = Self.testHost
    }

    override func tearDown() {
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAPIClient(
        maxRetryAttempts: Int = 0,
        requestTimeout: Double = 5
    ) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]

        return APIClient(
            serverURL: Self.testBaseURL,
            configuration: TestConfiguration.fast(
                maxRetryAttempts: maxRetryAttempts,
                requestTimeout: requestTimeout
            ),
            sessionConfiguration: config
        )
    }

    private func makePairingManager(
        maxRetryAttempts: Int = 0,
        requestTimeout: Double = 5
    ) -> PairingManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]

        return PairingManager(
            serverURL: Self.testBaseURL,
            configuration: TestConfiguration.fast(
                maxRetryAttempts: maxRetryAttempts,
                requestTimeout: requestTimeout
            ),
            sessionConfiguration: config
        )
    }

    // MARK: - JSON Helpers

    private func sessionJSON(
        status: String = "pending",
        code: String = "TEST123",
        modelName: String = "llama-3b",
        downloadURL: String? = nil,
        downloadFormat: String? = nil,
        downloadSizeBytes: Int? = nil
    ) -> [String: Any] {
        var json: [String: Any] = [
            "id": "session-uuid-123",
            "code": code,
            "model_name": modelName,
            "status": status,
        ]
        if let url = downloadURL { json["download_url"] = url }
        if let format = downloadFormat { json["download_format"] = format }
        if let size = downloadSizeBytes { json["download_size_bytes"] = size }
        return json
    }

    // MARK: - PairingModels Tests

    func testPairingStatusRawValues() {
        XCTAssertEqual(PairingStatus.pending.rawValue, "pending")
        XCTAssertEqual(PairingStatus.connected.rawValue, "connected")
        XCTAssertEqual(PairingStatus.deploying.rawValue, "deploying")
        XCTAssertEqual(PairingStatus.done.rawValue, "done")
        XCTAssertEqual(PairingStatus.expired.rawValue, "expired")
        XCTAssertEqual(PairingStatus.cancelled.rawValue, "cancelled")
    }

    func testPairingSessionDecoding() throws {
        let json: [String: Any] = [
            "id": "sess-1",
            "code": "ABC123",
            "model_name": "test-model",
            "status": "connected",
            "download_url": "https://cdn.example.com/model.mlmodel",
            "download_format": "coreml",
            "download_size_bytes": 50_000_000,
            "device_tier": "iphone_15_pro",
            "quantization": "q4",
            "executor": "coreml",
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        let session = try decoder.decode(PairingSession.self, from: data)

        XCTAssertEqual(session.id, "sess-1")
        XCTAssertEqual(session.code, "ABC123")
        XCTAssertEqual(session.modelName, "test-model")
        XCTAssertEqual(session.status, .connected)
        XCTAssertEqual(session.downloadURL, "https://cdn.example.com/model.mlmodel")
        XCTAssertEqual(session.downloadFormat, "coreml")
        XCTAssertEqual(session.downloadSizeBytes, 50_000_000)
        XCTAssertEqual(session.deviceTier, "iphone_15_pro")
        XCTAssertEqual(session.quantization, "q4")
        XCTAssertEqual(session.executor, "coreml")
    }

    func testPairingSessionDecodingMinimalFields() throws {
        let json: [String: Any] = [
            "id": "sess-2",
            "code": "XYZ",
            "model_name": "tiny-model",
            "status": "pending",
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        let session = try decoder.decode(PairingSession.self, from: data)

        XCTAssertEqual(session.id, "sess-2")
        XCTAssertEqual(session.status, .pending)
        XCTAssertNil(session.downloadURL)
        XCTAssertNil(session.downloadFormat)
        XCTAssertNil(session.downloadSizeBytes)
        XCTAssertNil(session.modelVersion)
        XCTAssertNil(session.deviceTier)
        XCTAssertNil(session.quantization)
        XCTAssertNil(session.executor)
    }

    func testDeploymentInfoInit() {
        let info = DeploymentInfo(
            modelName: "test-model",
            modelVersion: "v1.0",
            downloadURL: "https://example.com/model",
            format: "coreml",
            quantization: "fp16",
            executor: "coreml",
            sizeBytes: 100_000
        )

        XCTAssertEqual(info.modelName, "test-model")
        XCTAssertEqual(info.modelVersion, "v1.0")
        XCTAssertEqual(info.downloadURL, "https://example.com/model")
        XCTAssertEqual(info.format, "coreml")
        XCTAssertEqual(info.quantization, "fp16")
        XCTAssertEqual(info.executor, "coreml")
        XCTAssertEqual(info.sizeBytes, 100_000)
    }

    func testBenchmarkReportCodable() throws {
        let report = BenchmarkReport(
            modelName: "llama-3b",
            deviceName: "iPhone 15 Pro",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            ttftMs: 45.2,
            tpotMs: 12.3,
            tokensPerSecond: 81.3,
            p50LatencyMs: 11.8,
            p95LatencyMs: 15.2,
            p99LatencyMs: 22.1,
            memoryPeakBytes: 524_288_000,
            inferenceCount: 53,
            modelLoadTimeMs: 1200.0,
            coldInferenceMs: 78.5,
            warmInferenceMs: 11.2,
            batteryLevel: 0.85,
            thermalState: "nominal"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BenchmarkReport.self, from: data)

        XCTAssertEqual(decoded.modelName, "llama-3b")
        XCTAssertEqual(decoded.deviceName, "iPhone 15 Pro")
        XCTAssertEqual(decoded.chipFamily, "A17 Pro")
        XCTAssertEqual(decoded.ramGB, 8.0)
        XCTAssertEqual(decoded.osVersion, "17.4")
        XCTAssertEqual(decoded.ttftMs, 45.2, accuracy: 0.01)
        XCTAssertEqual(decoded.tpotMs, 12.3, accuracy: 0.01)
        XCTAssertEqual(decoded.tokensPerSecond, 81.3, accuracy: 0.01)
        XCTAssertEqual(decoded.p50LatencyMs, 11.8, accuracy: 0.01)
        XCTAssertEqual(decoded.p95LatencyMs, 15.2, accuracy: 0.01)
        XCTAssertEqual(decoded.p99LatencyMs, 22.1, accuracy: 0.01)
        XCTAssertEqual(decoded.memoryPeakBytes, 524_288_000)
        XCTAssertEqual(decoded.inferenceCount, 53)
        XCTAssertEqual(decoded.modelLoadTimeMs, 1200.0, accuracy: 0.01)
        XCTAssertEqual(decoded.coldInferenceMs, 78.5, accuracy: 0.01)
        XCTAssertEqual(decoded.warmInferenceMs, 11.2, accuracy: 0.01)
        XCTAssertEqual(decoded.batteryLevel ?? -1, 0.85, accuracy: 0.01)
        XCTAssertEqual(decoded.thermalState, "nominal")
        // New optional fields should be nil when not provided
        XCTAssertNil(decoded.promptTokens)
        XCTAssertNil(decoded.completionTokens)
        XCTAssertNil(decoded.contextLength)
        XCTAssertNil(decoded.totalTokens)
        XCTAssertNil(decoded.activeDelegate)
        XCTAssertNil(decoded.disabledDelegates)
    }

    func testBenchmarkReportSnakeCaseKeys() throws {
        let json: [String: Any] = [
            "model_name": "test",
            "device_name": "iPhone",
            "chip_family": "A17",
            "ram_gb": 8.0,
            "os_version": "17.0",
            "ttft_ms": 50.0,
            "tpot_ms": 10.0,
            "tokens_per_second": 100.0,
            "p50_latency_ms": 9.5,
            "p95_latency_ms": 14.0,
            "p99_latency_ms": 20.0,
            "memory_peak_bytes": 500_000_000,
            "inference_count": 53,
            "model_load_time_ms": 1000.0,
            "cold_inference_ms": 60.0,
            "warm_inference_ms": 9.0,
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        let report = try decoder.decode(BenchmarkReport.self, from: data)

        XCTAssertEqual(report.modelName, "test")
        XCTAssertEqual(report.tokensPerSecond, 100.0)
        XCTAssertEqual(report.inferenceCount, 53)
        XCTAssertNil(report.batteryLevel)
        XCTAssertNil(report.thermalState)
        // New optional fields absent from JSON should decode as nil
        XCTAssertNil(report.promptTokens)
        XCTAssertNil(report.completionTokens)
        XCTAssertNil(report.contextLength)
        XCTAssertNil(report.totalTokens)
        XCTAssertNil(report.activeDelegate)
        XCTAssertNil(report.disabledDelegates)
    }

    // MARK: - PairingDeviceCapabilities Tests

    func testDeviceCapabilitiesManualInit() {
        let caps = PairingDeviceCapabilities(
            deviceName: "iPhone 15 Pro",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            npuAvailable: true,
            gpuAvailable: true
        )

        XCTAssertEqual(caps.deviceName, "iPhone 15 Pro")
        XCTAssertEqual(caps.chipFamily, "A17 Pro")
        XCTAssertEqual(caps.ramGB, 8.0)
        XCTAssertEqual(caps.osVersion, "17.4")
        XCTAssertTrue(caps.npuAvailable)
        XCTAssertTrue(caps.gpuAvailable)
    }

    func testDeviceCapabilitiesCurrentDetection() {
        let caps = PairingDeviceCapabilities.current()

        // On any platform, these should be non-empty
        XCTAssertFalse(caps.deviceName.isEmpty)
        XCTAssertFalse(caps.chipFamily.isEmpty)
        XCTAssertGreaterThan(caps.ramGB, 0)
        XCTAssertFalse(caps.osVersion.isEmpty)
        // GPU should always be true
        XCTAssertTrue(caps.gpuAvailable)
    }

    // MARK: - PairingError Tests

    func testPairingErrorDescriptions() {
        let errors: [(PairingError, String)] = [
            (.sessionNotFound(code: "ABC"), "Pairing session not found for code: ABC"),
            (.sessionExpired, "Pairing session has expired."),
            (.sessionCancelled, "Pairing session was cancelled."),
            (.deploymentTimeout, "Timed out waiting for model deployment."),
            (.invalidDeployment(reason: "missing URL"), "Invalid deployment: missing URL"),
            (.downloadFailed(reason: "404"), "Model download failed: 404"),
            (.benchmarkFailed(reason: "no input"), "Benchmark failed: no input"),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    // MARK: - APIClient Pairing Endpoint Tests

    func testGetPairingSessionSendsGetRequest() async throws {
        let client = makeAPIClient()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "pending")),
        ]

        let session = try await client.getPairingSession(code: "TEST123")

        XCTAssertEqual(session.status, .pending)
        XCTAssertEqual(session.code, "TEST123")
        XCTAssertEqual(session.modelName, "llama-3b")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url?.path.contains("api/v1/deploy/pair/TEST123") == true)
        // Pairing requests should NOT have Authorization header
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        // But should have User-Agent
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "octomil-ios/1.0")
    }

    func testConnectToPairingSendsPostWithDeviceInfo() async throws {
        let client = makeAPIClient()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "connected")),
        ]

        let session = try await client.connectToPairing(
            code: "TEST123",
            deviceId: "device-uuid",
            platform: "ios",
            deviceName: "iPhone 15 Pro",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            npuAvailable: true,
            gpuAvailable: true
        )

        XCTAssertEqual(session.status, .connected)

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.contains("api/v1/deploy/pair/TEST123/connect") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        // Verify body contains device info
        let body = try XCTUnwrap(request.httpBody)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(parsed["device_id"] as? String, "device-uuid")
        XCTAssertEqual(parsed["platform"] as? String, "ios")
        XCTAssertEqual(parsed["device_name"] as? String, "iPhone 15 Pro")
        XCTAssertEqual(parsed["chip_family"] as? String, "A17 Pro")
        XCTAssertEqual(parsed["ram_gb"] as? Double, 8.0)
        XCTAssertEqual(parsed["os_version"] as? String, "17.4")
        XCTAssertEqual(parsed["npu_available"] as? Bool, true)
        XCTAssertEqual(parsed["gpu_available"] as? Bool, true)
    }

    func testSubmitPairingBenchmarkSendsPost() async throws {
        let client = makeAPIClient()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [:]),
        ]

        let report = BenchmarkReport(
            modelName: "test-model",
            deviceName: "iPhone 15 Pro",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            ttftMs: 50.0,
            tpotMs: 10.0,
            tokensPerSecond: 100.0,
            p50LatencyMs: 9.5,
            p95LatencyMs: 14.0,
            p99LatencyMs: 20.0,
            memoryPeakBytes: 500_000_000,
            inferenceCount: 53,
            modelLoadTimeMs: 1000.0,
            coldInferenceMs: 60.0,
            warmInferenceMs: 9.0,
            activeDelegate: "neural_engine",
            disabledDelegates: [],
            batteryLevel: 0.9,
            thermalState: "nominal"
        )

        try await client.submitPairingBenchmark(code: "TEST123", report: report)

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.contains("api/v1/deploy/pair/TEST123/benchmark") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        // Verify body contains benchmark data
        let body = try XCTUnwrap(request.httpBody)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(parsed["model_name"] as? String, "test-model")
        XCTAssertEqual(parsed["tokens_per_second"] as? Double, 100.0)
        XCTAssertEqual(parsed["thermal_state"] as? String, "nominal")
    }

    func testGetPairingSession404ThrowsServerError() async throws {
        let client = makeAPIClient()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 404, json: ["detail": "Session not found"]),
        ]

        do {
            _ = try await client.getPairingSession(code: "INVALID")
            XCTFail("Expected server error")
        } catch let error as OctomilError {
            if case .serverError(let statusCode, let message) = error {
                XCTAssertEqual(statusCode, 404)
                XCTAssertTrue(message.contains("not found"))
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        }
    }

    // MARK: - PairingManager Connect Tests

    func testConnectSendsDeviceCapabilities() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "connected")),
        ]

        let caps = PairingDeviceCapabilities(
            deviceName: "Test Device",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            npuAvailable: true,
            gpuAvailable: true
        )

        let session = try await manager.connect(code: "TEST123", deviceCapabilities: caps)

        XCTAssertEqual(session.status, .connected)
        XCTAssertEqual(session.modelName, "llama-3b")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(parsed["device_name"] as? String, "Test Device")
        XCTAssertEqual(parsed["chip_family"] as? String, "A17 Pro")
    }

    // MARK: - PairingManager WaitForDeployment Tests

    func testWaitForDeploymentReturnsWhenDeploying() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            // First poll: still connected
            .success(statusCode: 200, json: sessionJSON(status: "connected")),
            // Second poll: deploying with download URL
            .success(statusCode: 200, json: sessionJSON(
                status: "deploying",
                downloadURL: "https://cdn.example.com/model.mlmodel",
                downloadFormat: "coreml",
                downloadSizeBytes: 50_000_000
            )),
        ]

        let deployment = try await manager.waitForDeployment(code: "TEST123", timeout: 10)

        XCTAssertEqual(deployment.modelName, "llama-3b")
        XCTAssertEqual(deployment.downloadURL, "https://cdn.example.com/model.mlmodel")
        XCTAssertEqual(deployment.format, "coreml")
        XCTAssertEqual(deployment.sizeBytes, 50_000_000)
    }

    func testWaitForDeploymentThrowsOnExpired() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "expired")),
        ]

        do {
            _ = try await manager.waitForDeployment(code: "TEST123", timeout: 5)
            XCTFail("Expected sessionExpired error")
        } catch let error as PairingError {
            if case .sessionExpired = error {
                // Expected
            } else {
                XCTFail("Expected sessionExpired, got \(error)")
            }
        }
    }

    func testWaitForDeploymentThrowsOnCancelled() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "cancelled")),
        ]

        do {
            _ = try await manager.waitForDeployment(code: "TEST123", timeout: 5)
            XCTFail("Expected sessionCancelled error")
        } catch let error as PairingError {
            if case .sessionCancelled = error {
                // Expected
            } else {
                XCTFail("Expected sessionCancelled, got \(error)")
            }
        }
    }

    func testWaitForDeploymentThrowsOnMissingDownloadURL() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            // Deploying but no download URL
            .success(statusCode: 200, json: sessionJSON(status: "deploying")),
        ]

        do {
            _ = try await manager.waitForDeployment(code: "TEST123", timeout: 5)
            XCTFail("Expected invalidDeployment error")
        } catch let error as PairingError {
            if case .invalidDeployment(let reason) = error {
                XCTAssertTrue(reason.contains("missing"))
            } else {
                XCTFail("Expected invalidDeployment, got \(error)")
            }
        }
    }

    // MARK: - BenchmarkReport Encoding Tests

    func testBenchmarkReportEncodesSnakeCase() throws {
        let report = BenchmarkReport(
            modelName: "test",
            deviceName: "iPhone",
            chipFamily: "A17",
            ramGB: 8.0,
            osVersion: "17.0",
            ttftMs: 50.0,
            tpotMs: 10.0,
            tokensPerSecond: 100.0,
            p50LatencyMs: 9.5,
            p95LatencyMs: 14.0,
            p99LatencyMs: 20.0,
            memoryPeakBytes: 500_000_000,
            inferenceCount: 53,
            modelLoadTimeMs: 1000.0,
            coldInferenceMs: 60.0,
            warmInferenceMs: 9.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify snake_case keys
        XCTAssertNotNil(json["model_name"])
        XCTAssertNotNil(json["device_name"])
        XCTAssertNotNil(json["chip_family"])
        XCTAssertNotNil(json["ram_gb"])
        XCTAssertNotNil(json["os_version"])
        XCTAssertNotNil(json["ttft_ms"])
        XCTAssertNotNil(json["tpot_ms"])
        XCTAssertNotNil(json["tokens_per_second"])
        XCTAssertNotNil(json["p50_latency_ms"])
        XCTAssertNotNil(json["p95_latency_ms"])
        XCTAssertNotNil(json["p99_latency_ms"])
        XCTAssertNotNil(json["memory_peak_bytes"])
        XCTAssertNotNil(json["inference_count"])
        XCTAssertNotNil(json["model_load_time_ms"])
        XCTAssertNotNil(json["cold_inference_ms"])
        XCTAssertNotNil(json["warm_inference_ms"])
    }

    // MARK: - BenchmarkReport Token Fields Tests

    func testBenchmarkReportWithTokenFields() throws {
        let report = BenchmarkReport(
            modelName: "llama-7b",
            deviceName: "iPhone 16 Pro",
            chipFamily: "A18 Pro",
            ramGB: 8.0,
            osVersion: "18.0",
            ttftMs: 120.5,
            tpotMs: 15.3,
            tokensPerSecond: 65.4,
            p50LatencyMs: 14.8,
            p95LatencyMs: 18.2,
            p99LatencyMs: 25.1,
            memoryPeakBytes: 1_073_741_824,
            inferenceCount: 53,
            modelLoadTimeMs: 2500.0,
            coldInferenceMs: 150.0,
            warmInferenceMs: 14.5,
            promptTokens: 128,
            completionTokens: 256,
            contextLength: 2048,
            totalTokens: 384
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify token fields are encoded with snake_case keys
        XCTAssertEqual(json["prompt_tokens"] as? Int, 128)
        XCTAssertEqual(json["completion_tokens"] as? Int, 256)
        XCTAssertEqual(json["context_length"] as? Int, 2048)
        XCTAssertEqual(json["total_tokens"] as? Int, 384)

        // Round-trip decode
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        XCTAssertEqual(decoded.promptTokens, 128)
        XCTAssertEqual(decoded.completionTokens, 256)
        XCTAssertEqual(decoded.contextLength, 2048)
        XCTAssertEqual(decoded.totalTokens, 384)
    }

    func testBenchmarkReportTokenFieldsDecodeFromJSON() throws {
        let json: [String: Any] = [
            "model_name": "test",
            "device_name": "iPhone",
            "chip_family": "A17",
            "ram_gb": 8.0,
            "os_version": "17.0",
            "ttft_ms": 50.0,
            "tpot_ms": 10.0,
            "tokens_per_second": 100.0,
            "p50_latency_ms": 9.5,
            "p95_latency_ms": 14.0,
            "p99_latency_ms": 20.0,
            "memory_peak_bytes": 500_000_000,
            "inference_count": 53,
            "model_load_time_ms": 1000.0,
            "cold_inference_ms": 60.0,
            "warm_inference_ms": 9.0,
            "prompt_tokens": 64,
            "completion_tokens": 128,
            "context_length": 4096,
            "total_tokens": 192,
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let report = try JSONDecoder().decode(BenchmarkReport.self, from: data)

        XCTAssertEqual(report.promptTokens, 64)
        XCTAssertEqual(report.completionTokens, 128)
        XCTAssertEqual(report.contextLength, 4096)
        XCTAssertEqual(report.totalTokens, 192)
    }

    // MARK: - BenchmarkReport Delegate Fields Tests

    func testBenchmarkReportWithDelegateFields() throws {
        let report = BenchmarkReport(
            modelName: "llama-3b",
            deviceName: "iPhone 15 Pro",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            ttftMs: 45.0,
            tpotMs: 12.0,
            tokensPerSecond: 83.3,
            p50LatencyMs: 11.5,
            p95LatencyMs: 15.0,
            p99LatencyMs: 21.0,
            memoryPeakBytes: 524_288_000,
            inferenceCount: 53,
            modelLoadTimeMs: 1200.0,
            coldInferenceMs: 78.0,
            warmInferenceMs: 11.0,
            activeDelegate: "neural_engine",
            disabledDelegates: []
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify delegate fields are encoded with snake_case keys
        XCTAssertEqual(json["active_delegate"] as? String, "neural_engine")
        XCTAssertNotNil(json["disabled_delegates"])

        // Round-trip decode
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        XCTAssertEqual(decoded.activeDelegate, "neural_engine")
        XCTAssertEqual(decoded.disabledDelegates, [])
    }

    func testBenchmarkReportWithDisabledDelegates() throws {
        let report = BenchmarkReport(
            modelName: "tiny-model",
            deviceName: "iPhone 14",
            chipFamily: "A15 Bionic",
            ramGB: 6.0,
            osVersion: "17.2",
            ttftMs: 80.0,
            tpotMs: 20.0,
            tokensPerSecond: 50.0,
            p50LatencyMs: 19.0,
            p95LatencyMs: 25.0,
            p99LatencyMs: 30.0,
            memoryPeakBytes: 256_000_000,
            inferenceCount: 53,
            modelLoadTimeMs: 800.0,
            coldInferenceMs: 100.0,
            warmInferenceMs: 18.0,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine", "gpu"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)

        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        XCTAssertEqual(decoded.activeDelegate, "cpu")
        XCTAssertEqual(decoded.disabledDelegates, ["neural_engine", "gpu"])
    }

    func testBenchmarkReportDelegateFieldsDecodeFromJSON() throws {
        let json: [String: Any] = [
            "model_name": "test",
            "device_name": "iPhone",
            "chip_family": "A17",
            "ram_gb": 8.0,
            "os_version": "17.0",
            "ttft_ms": 50.0,
            "tpot_ms": 10.0,
            "tokens_per_second": 100.0,
            "p50_latency_ms": 9.5,
            "p95_latency_ms": 14.0,
            "p99_latency_ms": 20.0,
            "memory_peak_bytes": 500_000_000,
            "inference_count": 53,
            "model_load_time_ms": 1000.0,
            "cold_inference_ms": 60.0,
            "warm_inference_ms": 9.0,
            "active_delegate": "gpu",
            "disabled_delegates": ["neural_engine"],
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let report = try JSONDecoder().decode(BenchmarkReport.self, from: data)

        XCTAssertEqual(report.activeDelegate, "gpu")
        XCTAssertEqual(report.disabledDelegates, ["neural_engine"])
    }

    func testBenchmarkReportAllNewFieldsCombined() throws {
        let report = BenchmarkReport(
            modelName: "llama-7b-chat",
            deviceName: "iPhone 16 Pro Max",
            chipFamily: "A18 Pro",
            ramGB: 8.0,
            osVersion: "18.0",
            ttftMs: 95.0,
            tpotMs: 11.0,
            tokensPerSecond: 90.9,
            p50LatencyMs: 10.5,
            p95LatencyMs: 14.0,
            p99LatencyMs: 19.0,
            memoryPeakBytes: 1_500_000_000,
            inferenceCount: 53,
            modelLoadTimeMs: 3000.0,
            coldInferenceMs: 130.0,
            warmInferenceMs: 10.0,
            promptTokens: 256,
            completionTokens: 512,
            contextLength: 8192,
            totalTokens: 768,
            activeDelegate: "neural_engine",
            disabledDelegates: [],
            batteryLevel: 0.72,
            thermalState: "fair"
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)

        // Token fields
        XCTAssertEqual(decoded.promptTokens, 256)
        XCTAssertEqual(decoded.completionTokens, 512)
        XCTAssertEqual(decoded.contextLength, 8192)
        XCTAssertEqual(decoded.totalTokens, 768)

        // Delegate fields
        XCTAssertEqual(decoded.activeDelegate, "neural_engine")
        XCTAssertEqual(decoded.disabledDelegates, [])

        // Existing context fields still work
        XCTAssertEqual(decoded.batteryLevel ?? -1, 0.72, accuracy: 0.01)
        XCTAssertEqual(decoded.thermalState, "fair")

        // Inference count reflects 50 warm + overhead
        XCTAssertEqual(decoded.inferenceCount, 53)
    }

    // MARK: - PairingSession CodingKeys Tests

    func testPairingSessionEncodesSnakeCase() throws {
        let json: [String: Any] = [
            "id": "s1",
            "code": "X",
            "model_name": "m",
            "model_version": "v1",
            "status": "done",
            "download_url": "https://x.com/m",
            "download_format": "coreml",
            "download_size_bytes": 1000,
            "device_tier": "iphone_15_pro",
            "quantization": "q4",
            "executor": "coreml",
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let session = try JSONDecoder().decode(PairingSession.self, from: data)

        XCTAssertEqual(session.modelVersion, "v1")
        XCTAssertEqual(session.status, .done)
        XCTAssertEqual(session.deviceTier, "iphone_15_pro")
    }

    // MARK: - PairingManager submitBenchmark Tests

    func testSubmitBenchmarkSendsToCorrectEndpoint() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [:]),
        ]

        let report = BenchmarkReport(
            modelName: "bench-model",
            deviceName: "iPhone 15 Pro",
            chipFamily: "A17 Pro",
            ramGB: 8.0,
            osVersion: "17.4",
            ttftMs: 40.0,
            tpotMs: 8.0,
            tokensPerSecond: 125.0,
            p50LatencyMs: 7.5,
            p95LatencyMs: 12.0,
            p99LatencyMs: 18.0,
            memoryPeakBytes: 400_000_000,
            inferenceCount: 53,
            modelLoadTimeMs: 900.0,
            coldInferenceMs: 55.0,
            warmInferenceMs: 7.0
        )

        try await manager.submitBenchmark(code: "CODE42", report: report)

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.contains("api/v1/deploy/pair/CODE42/benchmark") == true)
    }

    // MARK: - PairingManager WaitForDeployment Timeout Tests

    func testWaitForDeploymentReturnsOnDoneStatus() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(
                status: "done",
                downloadURL: "https://cdn.example.com/final.mlmodel",
                downloadFormat: "coreml"
            )),
        ]

        let deployment = try await manager.waitForDeployment(code: "TEST123", timeout: 5)

        XCTAssertEqual(deployment.modelName, "llama-3b")
        XCTAssertEqual(deployment.downloadURL, "https://cdn.example.com/final.mlmodel")
        XCTAssertEqual(deployment.modelVersion, "latest") // default when nil
    }

    // MARK: - PairingManager Connect Uses Auto Caps

    func testConnectUsesAutoDetectedCapsWhenNoneProvided() async throws {
        let manager = makePairingManager()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "connected")),
        ]

        // Call without explicit caps — should auto-detect
        let session = try await manager.connect(code: "AUTO")

        XCTAssertEqual(session.status, .connected)

        // Verify the request was sent with device info
        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(parsed["device_name"])
        XCTAssertNotNil(parsed["platform"])
        XCTAssertEqual(parsed["platform"] as? String, "ios")
    }

    // MARK: - DeploymentInfo Optional Fields

    func testDeploymentInfoOptionalFields() {
        let minimal = DeploymentInfo(
            modelName: "m",
            modelVersion: "v1",
            downloadURL: "https://x.com/m",
            format: "coreml"
        )

        XCTAssertEqual(minimal.modelName, "m")
        XCTAssertNil(minimal.quantization)
        XCTAssertNil(minimal.executor)
        XCTAssertNil(minimal.sizeBytes)
    }

    // MARK: - ConnectToPairing with nil optional fields

    func testConnectToPairingOmitsNilFields() async throws {
        let client = makeAPIClient()

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: sessionJSON(status: "connected")),
        ]

        _ = try await client.connectToPairing(
            code: "TEST",
            deviceId: "d1",
            platform: "ios",
            deviceName: "iPhone",
            chipFamily: nil,
            ramGB: nil,
            osVersion: nil,
            npuAvailable: nil,
            gpuAvailable: nil
        )

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Required fields present
        XCTAssertEqual(parsed["device_id"] as? String, "d1")
        XCTAssertEqual(parsed["device_name"] as? String, "iPhone")

        // Optional fields should be absent
        XCTAssertNil(parsed["chip_family"])
        XCTAssertNil(parsed["ram_gb"])
        XCTAssertNil(parsed["os_version"])
        XCTAssertNil(parsed["npu_available"])
        XCTAssertNil(parsed["gpu_available"])
    }

    // MARK: - PairingStatus Decoding

    func testAllPairingStatusesCanBeDecoded() throws {
        let statuses = ["pending", "connected", "deploying", "done", "expired", "cancelled"]
        let expected: [PairingStatus] = [.pending, .connected, .deploying, .done, .expired, .cancelled]

        for (raw, expected) in zip(statuses, expected) {
            let json: [String: Any] = [
                "id": "s1",
                "code": "X",
                "model_name": "m",
                "status": raw,
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            let session = try JSONDecoder().decode(PairingSession.self, from: data)
            XCTAssertEqual(session.status, expected, "Failed for status: \(raw)")
        }
    }
}

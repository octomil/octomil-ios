import Foundation
import XCTest
import CoreML
@testable import Octomil

/// Tests for the runtime adaptation subsystem: DeviceStateMonitor, RuntimeAdapter,
/// AdaptiveModelLoader, and the API client adaptation/fallback endpoints.
final class RuntimeAdaptationTests: XCTestCase {

    // MARK: - RuntimeAdapter Tests

    func testCriticalThermalRecommendsCPUOnlyWithThrottle() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .charging,
            thermalState: .critical,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuOnly)
        XCTAssertTrue(rec.shouldThrottle)
        XCTAssertTrue(rec.reduceBatchSize)
        XCTAssertEqual(rec.maxConcurrentInferences, 1)
        XCTAssertTrue(rec.reason.lowercased().contains("hot") || rec.reason.lowercased().contains("critical"))
    }

    func testSeriousThermalRecommendsCPUAndGPU() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.90,
            batteryState: .charging,
            thermalState: .serious,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
        XCTAssertFalse(rec.shouldThrottle)
        XCTAssertEqual(rec.maxConcurrentInferences, 2)
    }

    func testBatteryCriticallyLowRecommendsCPUOnly() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.05,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuOnly)
        XCTAssertTrue(rec.reduceBatchSize)
        XCTAssertEqual(rec.maxConcurrentInferences, 1)
        XCTAssertTrue(rec.reason.lowercased().contains("battery"))
    }

    func testBatteryLowUnpluggedRecommendsCPUAndGPU() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.15,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
        XCTAssertFalse(rec.shouldThrottle)
        XCTAssertEqual(rec.maxConcurrentInferences, 2)
        XCTAssertTrue(rec.reason.lowercased().contains("battery") || rec.reason.lowercased().contains("conserv"))
    }

    func testBatteryLowButChargingRecommendsAll() {
        // When charging, battery < 20% should NOT trigger battery conservation
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.15,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        // Should fall through to nominal since charging cancels the unplugged check
        XCTAssertEqual(rec.computeUnits, .all)
        XCTAssertEqual(rec.maxConcurrentInferences, 4)
    }

    func testLowPowerModeRecommendsReducedConcurrency() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.60,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: true
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
        XCTAssertEqual(rec.maxConcurrentInferences, 1)
        XCTAssertFalse(rec.shouldThrottle)
    }

    func testNominalStateRecommendsAllComputeUnits() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.85,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 4096,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .all)
        XCTAssertFalse(rec.shouldThrottle)
        XCTAssertFalse(rec.reduceBatchSize)
        XCTAssertEqual(rec.maxConcurrentInferences, 4)
    }

    func testFairThermalStateRecommendsAll() {
        // Fair thermal is not severe enough to trigger adaptation
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.70,
            batteryState: .unplugged,
            thermalState: .fair,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .all)
        XCTAssertFalse(rec.shouldThrottle)
    }

    func testCriticalThermalTakesPriorityOverLowBattery() {
        // Even if battery is low, critical thermal should take priority
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.05,
            batteryState: .unplugged,
            thermalState: .critical,
            availableMemoryMB: 512,
            isLowPowerMode: true
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuOnly)
        XCTAssertTrue(rec.shouldThrottle, "Critical thermal should always throttle")
    }

    func testSeriousThermalTakesPriorityOverLowBattery() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.05,
            batteryState: .unplugged,
            thermalState: .serious,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        // Serious thermal should trigger before battery check
        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
    }

    func testBatteryExactlyAtTenPercentNotCritical() {
        // 10% should NOT trigger the < 10% critical battery path
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.10,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        // 10% is in the 10-20% range for unplugged
        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
    }

    func testBatteryExactlyAtTwentyPercentIsNominal() {
        // 20% exactly should NOT trigger the < 20% path
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.20,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .all)
    }

    func testBatteryJustBelowTenPercentIsCritical() {
        // 0.099 is < 0.10, should trigger critical battery (CPU only)
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.099,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuOnly,
                       "Battery at 0.099 (< 0.10) should trigger CPU-only mode")
        XCTAssertTrue(rec.reduceBatchSize,
                      "Battery at 0.099 should reduce batch size")
        XCTAssertEqual(rec.maxConcurrentInferences, 1,
                       "Battery at 0.099 should limit to 1 concurrent inference")
    }

    func testBatteryJustBelowTwentyPercentUnpluggedIsCPUAndGPU() {
        // 0.199 is < 0.20 and unplugged, should trigger battery conservation
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.199,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuAndGPU,
                       "Battery at 0.199 (< 0.20) unplugged should bypass Neural Engine")
        XCTAssertEqual(rec.maxConcurrentInferences, 2,
                       "Battery at 0.199 should limit to 2 concurrent inferences")
    }

    func testBatteryAtExactlyZeroIsCritical() {
        // 0.0 is < 0.10, should trigger critical battery
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.0,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        XCTAssertEqual(rec.computeUnits, .cpuOnly,
                       "Battery at 0.0 should trigger CPU-only mode")
    }

    func testUnknownBatteryLevelTreatedAsNominal() {
        // UIDevice returns -1.0 when battery monitoring is off
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: -1.0,
            batteryState: .unknown,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = RuntimeAdapter.recommend(for: state)

        // Negative battery level should not trigger any battery checks
        XCTAssertEqual(rec.computeUnits, .all)
    }

    // MARK: - DeviceStateMonitor Tests

    func testDeviceStateMonitorInitialState() async {
        let monitor = DeviceStateMonitor()
        let state = await monitor.currentState

        // Before monitoring starts, battery level should be unknown
        XCTAssertEqual(state.batteryLevel, -1.0)
        XCTAssertEqual(state.batteryState, .unknown)
    }

    func testDeviceStateMonitorStartStop() async {
        let monitor = DeviceStateMonitor(pollingInterval: 1)

        await monitor.startMonitoring()
        // Starting again should be a no-op
        await monitor.startMonitoring()

        await monitor.stopMonitoring()
        // Stopping again should be a no-op
        await monitor.stopMonitoring()
    }

    func testDeviceStateMonitorStateAfterMonitoring() async {
        let monitor = DeviceStateMonitor(pollingInterval: 60)
        await monitor.startMonitoring()

        let state = await monitor.currentState

        // After monitoring starts, we should have real values (on macOS, battery=1.0/full)
        #if os(macOS)
        XCTAssertEqual(state.batteryLevel, 1.0)
        XCTAssertEqual(state.batteryState, .full)
        #endif

        // Memory should always be >= 0 after monitoring starts.
        // On iOS Simulator, os_proc_available_memory() may return 0.
        XCTAssertGreaterThanOrEqual(state.availableMemoryMB, 0)

        await monitor.stopMonitoring()
    }

    func testDeviceStateThermalStateEquatable() {
        let state1 = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.5,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )

        let state2 = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.5,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )

        let state3 = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.5,
            batteryState: .unplugged,
            thermalState: .serious,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testThermalStateComparable() {
        XCTAssertTrue(DeviceStateMonitor.ThermalState.nominal < .fair)
        XCTAssertTrue(DeviceStateMonitor.ThermalState.fair < .serious)
        XCTAssertTrue(DeviceStateMonitor.ThermalState.serious < .critical)
        XCTAssertFalse(DeviceStateMonitor.ThermalState.critical < .nominal)
    }

    func testBatteryStateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let states: [DeviceStateMonitor.BatteryState] = [.unknown, .unplugged, .charging, .full]

        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(DeviceStateMonitor.BatteryState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    func testThermalStateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let states: [DeviceStateMonitor.ThermalState] = [.nominal, .fair, .serious, .critical]

        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(DeviceStateMonitor.ThermalState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    // MARK: - ComputeRecommendation Tests

    func testComputeRecommendationEquatable() {
        let rec1 = RuntimeAdapter.ComputeRecommendation(
            computeUnits: .all,
            shouldThrottle: false,
            reduceBatchSize: false,
            maxConcurrentInferences: 4,
            reason: "Nominal"
        )

        let rec2 = RuntimeAdapter.ComputeRecommendation(
            computeUnits: .all,
            shouldThrottle: false,
            reduceBatchSize: false,
            maxConcurrentInferences: 4,
            reason: "Nominal"
        )

        let rec3 = RuntimeAdapter.ComputeRecommendation(
            computeUnits: .cpuOnly,
            shouldThrottle: true,
            reduceBatchSize: true,
            maxConcurrentInferences: 1,
            reason: "Critical"
        )

        XCTAssertEqual(rec1, rec2)
        XCTAssertNotEqual(rec1, rec3)
    }

    // MARK: - AdaptiveModelLoader Tests

    func testAdaptiveModelLoaderLoadErrorDescription() {
        let error = AdaptiveModelLoader.LoadError.allComputeUnitsFailed(
            errors: [
                (.all, NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "ANE failed"])),
                (.cpuAndGPU, NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "GPU failed"])),
                (.cpuOnly, NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "CPU failed"])),
            ]
        )

        let description = error.localizedDescription
        XCTAssertTrue(description.contains("ANE failed"))
        XCTAssertTrue(description.contains("GPU failed"))
        XCTAssertTrue(description.contains("CPU failed"))
        XCTAssertTrue(description.contains("all (ANE+GPU+CPU)"))
        XCTAssertTrue(description.contains("cpuAndGPU"))
        XCTAssertTrue(description.contains("cpuOnly"))
    }

    func testAdaptiveModelLoaderFailsWithBadURL() async {
        let loader = AdaptiveModelLoader()
        let badURL = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")

        do {
            _ = try await loader.load(from: badURL)
            XCTFail("Expected load to fail with bad URL")
        } catch let error as AdaptiveModelLoader.LoadError {
            if case .allComputeUnitsFailed(let errors) = error {
                XCTAssertEqual(errors.count, 3, "Should have tried all 3 compute unit configurations")
            } else {
                XCTFail("Unexpected error case")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAdaptiveModelLoaderFailsWithPreferredStart() async {
        let loader = AdaptiveModelLoader()
        let badURL = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")

        do {
            _ = try await loader.load(from: badURL, preferredComputeUnits: .cpuAndGPU)
            XCTFail("Expected load to fail with bad URL")
        } catch let error as AdaptiveModelLoader.LoadError {
            if case .allComputeUnitsFailed(let errors) = error {
                // Starting from .cpuAndGPU, should only try cpuAndGPU and cpuOnly (2 options)
                XCTAssertEqual(errors.count, 2, "Should have tried 2 compute unit configurations starting from cpuAndGPU")
            } else {
                XCTFail("Unexpected error case")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAdaptiveModelLoaderFailsWithCPUOnlyStart() async {
        let loader = AdaptiveModelLoader()
        let badURL = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")

        do {
            _ = try await loader.load(from: badURL, preferredComputeUnits: .cpuOnly)
            XCTFail("Expected load to fail with bad URL")
        } catch let error as AdaptiveModelLoader.LoadError {
            if case .allComputeUnitsFailed(let errors) = error {
                // Starting from .cpuOnly, should only try cpuOnly (1 option)
                XCTAssertEqual(errors.count, 1)
            } else {
                XCTFail("Unexpected error case")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - AdaptiveDeployedModel Tests

    func testAdaptiveModelErrorDescription() {
        let error = AdaptiveModelError.concurrencyLimitReached(limit: 2)
        XCTAssertTrue(error.localizedDescription.contains("2"))
        XCTAssertTrue(error.localizedDescription.lowercased().contains("concurrency"))
    }

    // MARK: - API Client Adaptation Endpoint Tests

    private static let testHost = "api.test.octomil.com"
    private static let testBaseURL = URL(string: "https://\(testHost)")!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = Self.testHost
    }

    private func makeAPIClient(maxRetryAttempts: Int = 1) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]

        return APIClient(
            serverURL: Self.testBaseURL,
            configuration: TestConfiguration.fast(maxRetryAttempts: maxRetryAttempts),
            sessionConfiguration: config
        )
    }

    func testGetAdaptationRecommendation() async throws {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "recommended_executor": "cpuAndGPU",
                "recommended_compute_units": "cpuAndGPU",
                "throttle_inference": false,
                "reduce_batch_size": true,
            ]),
        ]

        let recommendation = try await client.getAdaptationRecommendation(
            deviceId: "device-1",
            modelId: "model-1",
            batteryLevel: 0.15,
            thermalState: "nominal",
            currentFormat: "coreml",
            currentExecutor: "all"
        )

        XCTAssertEqual(recommendation.recommendedExecutor, "cpuAndGPU")
        XCTAssertEqual(recommendation.recommendedComputeUnits, "cpuAndGPU")
        XCTAssertFalse(recommendation.throttleInference)
        XCTAssertTrue(recommendation.reduceBatchSize)

        // Verify request
        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.contains("api/v1/devices/device-1/models/model-1/adapt") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-token")

        // Verify request body
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["thermal_state"] as? String, "nominal")
        XCTAssertEqual(body["current_format"] as? String, "coreml")
        XCTAssertEqual(body["current_executor"] as? String, "all")
    }

    func testGetAdaptationRecommendationServerError() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["detail": "Internal server error"]),
        ]

        do {
            _ = try await client.getAdaptationRecommendation(
                deviceId: "device-1",
                modelId: "model-1",
                batteryLevel: 0.5,
                thermalState: "nominal",
                currentFormat: "coreml",
                currentExecutor: "all"
            )
            XCTFail("Expected server error")
        } catch let error as OctomilError {
            if case .serverError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetFallbackRecommendation() async throws {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "fallback_format": "coreml",
                "fallback_executor": "cpuOnly",
                "download_url": "https://models.octomil.com/model-1/v2/coreml-cpu.mlmodelc",
            ]),
        ]

        let fallback = try await client.getFallback(
            deviceId: "device-1",
            modelId: "model-1",
            version: "1.0.0",
            failedFormat: "coreml",
            failedExecutor: "all",
            errorMessage: "Neural Engine compilation failed"
        )

        XCTAssertEqual(fallback.fallbackFormat, "coreml")
        XCTAssertEqual(fallback.fallbackExecutor, "cpuOnly")
        XCTAssertTrue(fallback.downloadURL.contains("coreml-cpu"))
        XCTAssertNil(fallback.runtimeConfig)

        // Verify request
        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.contains("api/v1/devices/device-1/models/model-1/fallback") == true)

        // Verify request body
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        XCTAssertEqual(body["version"], "1.0.0")
        XCTAssertEqual(body["failed_format"], "coreml")
        XCTAssertEqual(body["failed_executor"], "all")
        XCTAssertEqual(body["error_message"], "Neural Engine compilation failed")
    }

    func testGetFallbackWithRuntimeConfig() async throws {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "fallback_format": "coreml",
                "fallback_executor": "cpuOnly",
                "download_url": "https://models.octomil.com/fallback.mlmodelc",
                "runtime_config": [
                    "max_batch_size": 16,
                    "quantization": "int8",
                ],
            ]),
        ]

        let fallback = try await client.getFallback(
            deviceId: "d-1",
            modelId: "m-1",
            version: "2.0",
            failedFormat: "coreml",
            failedExecutor: "cpuAndGPU",
            errorMessage: "Out of memory"
        )

        XCTAssertNotNil(fallback.runtimeConfig)
    }

    func testGetFallbackAuthenticationRequired() async {
        let client = makeAPIClient()
        // Don't set token

        do {
            _ = try await client.getFallback(
                deviceId: "d-1",
                modelId: "m-1",
                version: "1.0",
                failedFormat: "coreml",
                failedExecutor: "all",
                errorMessage: "failed"
            )
            XCTFail("Expected authentication error")
        } catch let error as OctomilError {
            if case .authenticationFailed = error {
                // Expected
            } else {
                XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - API Models Codable Tests

    func testAdaptationRecommendationCodable() throws {
        let rec = AdaptationRecommendation(
            recommendedExecutor: "cpuOnly",
            recommendedComputeUnits: "cpuOnly",
            throttleInference: true,
            reduceBatchSize: true
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Test manual CodingKeys-based encoding (not snake_case strategy)
        let stdEncoder = JSONEncoder()
        let stdDecoder = JSONDecoder()

        let data = try stdEncoder.encode(rec)
        let decoded = try stdDecoder.decode(AdaptationRecommendation.self, from: data)

        XCTAssertEqual(decoded.recommendedExecutor, "cpuOnly")
        XCTAssertEqual(decoded.recommendedComputeUnits, "cpuOnly")
        XCTAssertTrue(decoded.throttleInference)
        XCTAssertTrue(decoded.reduceBatchSize)

        // Verify the encoded JSON uses snake_case keys from CodingKeys
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["recommended_executor"])
        XCTAssertNotNil(json["recommended_compute_units"])
        XCTAssertNotNil(json["throttle_inference"])
        XCTAssertNotNil(json["reduce_batch_size"])
    }

    func testFallbackRecommendationCodable() throws {
        let rec = FallbackRecommendation(
            fallbackFormat: "coreml",
            fallbackExecutor: "cpuOnly",
            downloadURL: "https://example.com/model.mlmodelc",
            runtimeConfig: nil
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(rec)
        let decoded = try decoder.decode(FallbackRecommendation.self, from: data)

        XCTAssertEqual(decoded.fallbackFormat, "coreml")
        XCTAssertEqual(decoded.fallbackExecutor, "cpuOnly")
        XCTAssertEqual(decoded.downloadURL, "https://example.com/model.mlmodelc")
        XCTAssertNil(decoded.runtimeConfig)

        // Verify snake_case keys
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["fallback_format"])
        XCTAssertNotNil(json["fallback_executor"])
        XCTAssertNotNil(json["download_url"])
    }

    func testFallbackRecommendationWithRuntimeConfigCodable() throws {
        let rec = FallbackRecommendation(
            fallbackFormat: "coreml",
            fallbackExecutor: "cpuOnly",
            downloadURL: "https://example.com/model.mlmodelc",
            runtimeConfig: ["max_batch_size": AnyCodable(16), "quantization": AnyCodable("int8")]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(rec)
        let decoded = try decoder.decode(FallbackRecommendation.self, from: data)

        XCTAssertNotNil(decoded.runtimeConfig)
        XCTAssertEqual(decoded.runtimeConfig?.count, 2)
    }

    // MARK: - DeployError Tests

    func testDeployErrorDescription() {
        let error = DeployError.unsupportedFormat("onnx")
        XCTAssertTrue(error.localizedDescription.contains("onnx"))
        XCTAssertTrue(error.localizedDescription.contains("Unsupported"))
    }

    // MARK: - Integration-Style Tests

    func testRuntimeAdapterAllScenariosCovered() {
        // Verify all thermal states produce valid recommendations
        let thermalStates: [DeviceStateMonitor.ThermalState] = [.nominal, .fair, .serious, .critical]

        for thermal in thermalStates {
            let state = DeviceStateMonitor.DeviceState(
                batteryLevel: 0.80,
                batteryState: .charging,
                thermalState: thermal,
                availableMemoryMB: 2048,
                isLowPowerMode: false
            )

            let rec = RuntimeAdapter.recommend(for: state)

            XCTAssertGreaterThan(rec.maxConcurrentInferences, 0, "Should always allow at least 1 inference")
            XCTAssertFalse(rec.reason.isEmpty, "Reason should always be provided")
        }
    }

    func testRuntimeAdapterBatteryEdgeCases() {
        // Test the full range of battery levels
        let batteryLevels: [Float] = [0.0, 0.01, 0.05, 0.09, 0.10, 0.15, 0.19, 0.20, 0.50, 1.0]

        for level in batteryLevels {
            let state = DeviceStateMonitor.DeviceState(
                batteryLevel: level,
                batteryState: .unplugged,
                thermalState: .nominal,
                availableMemoryMB: 2048,
                isLowPowerMode: false
            )

            let rec = RuntimeAdapter.recommend(for: state)

            // Every recommendation should be valid
            XCTAssertGreaterThan(rec.maxConcurrentInferences, 0)

            if level < 0.10 {
                XCTAssertEqual(rec.computeUnits, .cpuOnly,
                               "Battery at \(level) should use CPU only")
            } else if level < 0.20 {
                XCTAssertEqual(rec.computeUnits, .cpuAndGPU,
                               "Battery at \(level) unplugged should use CPU+GPU")
            } else {
                XCTAssertEqual(rec.computeUnits, .all,
                               "Battery at \(level) should use all compute")
            }
        }
    }

    func testDeviceStateMonitorStateStream() async {
        let monitor = DeviceStateMonitor(pollingInterval: 60)
        await monitor.startMonitoring()

        // The state stream should yield the initial state immediately
        let stream = await monitor.stateChanges
        var receivedState: DeviceStateMonitor.DeviceState?

        for await state in stream {
            receivedState = state
            break // Just get the first emission
        }

        XCTAssertNotNil(receivedState, "Should receive at least one state from the stream")

        await monitor.stopMonitoring()
    }

    // MARK: - Server-Backed Adaptation Tests

    func testServerAdaptationUsesServerResponse() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "recommended_executor": "cpuOnly",
                "recommended_compute_units": "cpuOnly",
                "throttle_inference": true,
                "reduce_batch_size": true,
            ]),
        ]

        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 4096,
            isLowPowerMode: false
        )

        let rec = await RuntimeAdapter.recommend(
            for: state,
            using: client,
            deviceId: "device-1",
            modelId: "model-1"
        )

        // Server said cpuOnly with throttle -- should override local "nominal" recommendation
        XCTAssertEqual(rec.computeUnits, .cpuOnly)
        XCTAssertTrue(rec.shouldThrottle)
        XCTAssertTrue(rec.reduceBatchSize)
        XCTAssertEqual(rec.maxConcurrentInferences, 1, "Throttled cpuOnly should limit to 1")
        XCTAssertTrue(rec.reason.contains("Server"))
    }

    func testServerAdaptationFallsBackToLocalOnServerError() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["detail": "Internal server error"]),
        ]

        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 4096,
            isLowPowerMode: false
        )

        let rec = await RuntimeAdapter.recommend(
            for: state,
            using: client,
            deviceId: "device-1",
            modelId: "model-1"
        )

        // Server error -- should fall back to local "nominal" recommendation
        XCTAssertEqual(rec.computeUnits, .all)
        XCTAssertFalse(rec.shouldThrottle)
        XCTAssertEqual(rec.maxConcurrentInferences, 4)
        XCTAssertTrue(rec.reason.contains("Nominal"))
    }

    func testServerAdaptationFallsBackWhenNoAPIClient() async {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.05,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = await RuntimeAdapter.recommend(
            for: state,
            using: nil,
            deviceId: nil,
            modelId: nil
        )

        // No API client -- should use local heuristics (battery critical)
        XCTAssertEqual(rec.computeUnits, .cpuOnly)
        XCTAssertTrue(rec.reduceBatchSize)
        XCTAssertEqual(rec.maxConcurrentInferences, 1)
    }

    func testServerAdaptationFallsBackWhenMissingDeviceId() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 4096,
            isLowPowerMode: false
        )

        // deviceId is nil -- should use local heuristics
        let rec = await RuntimeAdapter.recommend(
            for: state,
            using: client,
            deviceId: nil,
            modelId: "model-1"
        )

        XCTAssertEqual(rec.computeUnits, .all)
        XCTAssertTrue(rec.reason.contains("Nominal"))
    }

    func testServerAdaptationSendsCorrectRequestBody() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "recommended_executor": "all",
                "recommended_compute_units": "all",
                "throttle_inference": false,
                "reduce_batch_size": false,
            ]),
        ]

        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.75,
            batteryState: .unplugged,
            thermalState: .fair,
            availableMemoryMB: 3000,
            isLowPowerMode: false
        )

        _ = await RuntimeAdapter.recommend(
            for: state,
            using: client,
            deviceId: "device-42",
            modelId: "my-model",
            currentFormat: "mlx"
        )

        let request = try? XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertTrue(request?.url?.path.contains("api/v1/devices/device-42/models/my-model/adapt") == true)

        if let bodyData = request?.httpBody,
           let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            XCTAssertEqual(body["thermal_state"] as? String, "fair")
            XCTAssertEqual(body["current_format"] as? String, "mlx")
            // Battery level is Float, compare loosely
            XCTAssertNotNil(body["battery_level"])
        }
    }

    func testServerAdaptationCpuAndGPUResponse() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "recommended_executor": "cpuAndGPU",
                "recommended_compute_units": "cpuAndGPU",
                "throttle_inference": false,
                "reduce_batch_size": false,
            ]),
        ]

        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 4096,
            isLowPowerMode: false
        )

        let rec = await RuntimeAdapter.recommend(
            for: state,
            using: client,
            deviceId: "device-1",
            modelId: "model-1"
        )

        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
        XCTAssertFalse(rec.shouldThrottle)
        XCTAssertEqual(rec.maxConcurrentInferences, 2, "Non-throttled cpuAndGPU should allow 2 concurrent")
    }

    func testServerAdaptationFallsBackOnNetworkError() async {
        let client = makeAPIClient()
        await client.setDeviceToken("valid-token")

        // No responses queued -- triggers network error
        SharedMockURLProtocol.responses = [
            .failure(URLError(.notConnectedToInternet)),
        ]

        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.50,
            batteryState: .unplugged,
            thermalState: .serious,
            availableMemoryMB: 2048,
            isLowPowerMode: false
        )

        let rec = await RuntimeAdapter.recommend(
            for: state,
            using: client,
            deviceId: "device-1",
            modelId: "model-1"
        )

        // Network error -> local fallback for "serious" thermal
        XCTAssertEqual(rec.computeUnits, .cpuAndGPU)
        XCTAssertTrue(rec.reason.contains("hot") || rec.reason.contains("Neural Engine"))
    }

    // MARK: - Compute Units Parsing Tests

    func testParseComputeUnitsAll() {
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits("all"), .all)
    }

    func testParseComputeUnitsCpuOnly() {
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits("cpuOnly"), .cpuOnly)
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits("cpu_only"), .cpuOnly)
    }

    func testParseComputeUnitsCpuAndGPU() {
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits("cpuAndGPU"), .cpuAndGPU)
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits("cpu_and_gpu"), .cpuAndGPU)
    }

    func testParseComputeUnitsUnknownDefaultsToAll() {
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits("something_weird"), .all)
        XCTAssertEqual(RuntimeAdapter.parseComputeUnits(""), .all)
    }

    func testComputeUnitsToString() {
        XCTAssertEqual(RuntimeAdapter.computeUnitsToString(.all), "all")
        XCTAssertEqual(RuntimeAdapter.computeUnitsToString(.cpuOnly), "cpuOnly")
        XCTAssertEqual(RuntimeAdapter.computeUnitsToString(.cpuAndGPU), "cpuAndGPU")
        XCTAssertEqual(RuntimeAdapter.computeUnitsToString(.cpuAndNeuralEngine), "cpuAndNeuralEngine")
    }
}

import Foundation
import XCTest
@testable import Octomil

final class RuntimePlannerSchemasTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private let decoder = JSONDecoder()

    // MARK: - InstalledRuntime

    func testInstalledRuntimeDefaults() {
        let runtime = InstalledRuntime(engine: "coreml")
        XCTAssertEqual(runtime.engine, "coreml")
        XCTAssertNil(runtime.version)
        XCTAssertTrue(runtime.available)
        XCTAssertNil(runtime.accelerator)
        XCTAssertTrue(runtime.metadata.isEmpty)
    }

    func testInstalledRuntimeCodableRoundTrip() throws {
        let runtime = InstalledRuntime(
            engine: "mlx",
            version: "0.30.0",
            available: true,
            accelerator: "metal",
            metadata: ["info": "Metal 3"]
        )

        let data = try encoder.encode(runtime)
        let decoded = try decoder.decode(InstalledRuntime.self, from: data)

        XCTAssertEqual(decoded, runtime)
    }

    // MARK: - DeviceRuntimeProfile

    func testDeviceRuntimeProfileCodableRoundTrip() throws {
        let profile = DeviceRuntimeProfile(
            sdk: "ios",
            sdkVersion: "1.1.0",
            platform: "iOS",
            arch: "arm64",
            osVersion: "18.0",
            chip: "iPhone16,1",
            ramTotalBytes: 8_589_934_592,
            gpuCoreCount: 6,
            accelerators: ["metal", "ane"],
            installedRuntimes: [
                InstalledRuntime(engine: "coreml", available: true, accelerator: "ane"),
                InstalledRuntime(engine: "mlx", version: "0.30.0", available: true, accelerator: "metal"),
            ]
        )

        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(DeviceRuntimeProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }

    func testDeviceRuntimeProfileSnakeCaseKeys() throws {
        let profile = DeviceRuntimeProfile(
            sdk: "ios",
            sdkVersion: "1.0.0",
            platform: "iOS",
            arch: "arm64",
            osVersion: "18.0",
            ramTotalBytes: 4_000_000_000,
            gpuCoreCount: 6
        )

        let data = try encoder.encode(profile)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Snake-case keys from CodingKeys
        XCTAssertNotNil(json["sdk_version"])
        XCTAssertNotNil(json["ram_total_bytes"])
        XCTAssertNotNil(json["installed_runtimes"])
        XCTAssertNotNil(json["os_version"])
        XCTAssertNotNil(json["gpu_core_count"])

        // camelCase should NOT be present
        XCTAssertNil(json["sdkVersion"])
        XCTAssertNil(json["ramTotalBytes"])
        XCTAssertNil(json["installedRuntimes"])
    }

    // MARK: - RuntimeArtifactPlan

    func testRuntimeArtifactPlanCodableRoundTrip() throws {
        let artifact = RuntimeArtifactPlan(
            modelId: "llama-8b",
            artifactId: "art_123",
            modelVersion: "v2",
            format: "gguf",
            quantization: "q4_k_m",
            uri: "https://cdn.example.com/model.gguf",
            digest: "sha256:abc123",
            sizeBytes: 4_000_000_000,
            minRamBytes: 6_000_000_000
        )

        let data = try encoder.encode(artifact)
        let decoded = try decoder.decode(RuntimeArtifactPlan.self, from: data)

        XCTAssertEqual(decoded, artifact)
    }

    func testRuntimeArtifactPlanMinimalFields() throws {
        let artifact = RuntimeArtifactPlan(modelId: "test-model")

        let data = try encoder.encode(artifact)
        let decoded = try decoder.decode(RuntimeArtifactPlan.self, from: data)

        XCTAssertEqual(decoded.modelId, "test-model")
        XCTAssertNil(decoded.artifactId)
        XCTAssertNil(decoded.format)
    }

    // MARK: - RuntimeCandidatePlan

    func testRuntimeCandidatePlanCodableRoundTrip() throws {
        let candidate = RuntimeCandidatePlan(
            locality: .local,
            priority: 1,
            confidence: 0.95,
            reason: "Best engine for this device",
            engine: "mlx",
            engineVersionConstraint: ">=0.30.0",
            artifact: RuntimeArtifactPlan(modelId: "llama-8b", format: "safetensors"),
            benchmarkRequired: true
        )

        let data = try encoder.encode(candidate)
        let decoded = try decoder.decode(RuntimeCandidatePlan.self, from: data)

        XCTAssertEqual(decoded, candidate)
    }

    func testRuntimeLocalityEncoding() throws {
        let local = RuntimeLocality.local
        let cloud = RuntimeLocality.cloud

        let localData = try encoder.encode(local)
        let cloudData = try encoder.encode(cloud)

        XCTAssertEqual(String(data: localData, encoding: .utf8), "\"local\"")
        XCTAssertEqual(String(data: cloudData, encoding: .utf8), "\"cloud\"")
    }

    // MARK: - RuntimePlanResponse

    func testRuntimePlanResponseCodableRoundTrip() throws {
        let plan = RuntimePlanResponse(
            model: "gemma-2b",
            capability: "text",
            policy: "local_first",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 1,
                    confidence: 0.9,
                    reason: "High confidence local",
                    engine: "mlx"
                ),
                RuntimeCandidatePlan(
                    locality: .cloud,
                    priority: 2,
                    confidence: 0.8,
                    reason: "Cloud fallback"
                ),
            ],
            fallbackCandidates: [
                RuntimeCandidatePlan(
                    locality: .local,
                    priority: 10,
                    confidence: 0.5,
                    reason: "Slow but works",
                    engine: "coreml"
                ),
            ],
            planTtlSeconds: 86400,
            serverGeneratedAt: "2026-04-12T00:00:00Z"
        )

        let data = try encoder.encode(plan)
        let decoded = try decoder.decode(RuntimePlanResponse.self, from: data)

        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.candidates.count, 2)
        XCTAssertEqual(decoded.fallbackCandidates.count, 1)
        XCTAssertEqual(decoded.planTtlSeconds, 86400)
    }

    func testRuntimePlanResponseDefaults() {
        let plan = RuntimePlanResponse(
            model: "test",
            capability: "text",
            policy: "local_first",
            candidates: []
        )

        XCTAssertEqual(plan.planTtlSeconds, 604_800) // 7 days
        XCTAssertEqual(plan.serverGeneratedAt, "")
        XCTAssertTrue(plan.fallbackCandidates.isEmpty)
    }

    // MARK: - RuntimeSelection

    func testRuntimeSelectionDefaults() {
        let selection = RuntimeSelection(locality: .local)

        XCTAssertEqual(selection.locality, .local)
        XCTAssertNil(selection.engine)
        XCTAssertNil(selection.artifact)
        XCTAssertFalse(selection.benchmarkRan)
        XCTAssertEqual(selection.source, "")
        XCTAssertTrue(selection.fallbackCandidates.isEmpty)
        XCTAssertEqual(selection.reason, "")
    }

    func testRuntimeSelectionEquality() {
        let a = RuntimeSelection(locality: .cloud, engine: "openai", source: "server_plan", reason: "test")
        let b = RuntimeSelection(locality: .cloud, engine: "openai", source: "server_plan", reason: "test")
        let c = RuntimeSelection(locality: .local, engine: "mlx", source: "cache", reason: "different")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Server JSON Deserialization

    func testDeserializeServerPlanJSON() throws {
        // Simulate a JSON response from the server using snake_case
        let json = """
        {
            "model": "llama-8b",
            "capability": "text",
            "policy": "local_first",
            "candidates": [
                {
                    "locality": "local",
                    "priority": 1,
                    "confidence": 0.92,
                    "reason": "Optimal for M2 Pro",
                    "engine": "mlx",
                    "engine_version_constraint": null,
                    "artifact": {
                        "model_id": "llama-8b",
                        "artifact_id": "art_456",
                        "format": "safetensors",
                        "quantization": "q4_k_m",
                        "size_bytes": 4294967296,
                        "min_ram_bytes": 6442450944
                    },
                    "benchmark_required": false
                }
            ],
            "fallback_candidates": [],
            "plan_ttl_seconds": 604800,
            "server_generated_at": "2026-04-12T10:00:00Z"
        }
        """.data(using: .utf8)!

        let plan = try decoder.decode(RuntimePlanResponse.self, from: json)

        XCTAssertEqual(plan.model, "llama-8b")
        XCTAssertEqual(plan.candidates.count, 1)
        XCTAssertEqual(plan.candidates[0].engine, "mlx")
        XCTAssertEqual(plan.candidates[0].locality, .local)
        XCTAssertEqual(plan.candidates[0].artifact?.format, "safetensors")
        XCTAssertEqual(plan.candidates[0].artifact?.sizeBytes, 4_294_967_296)
        XCTAssertFalse(plan.candidates[0].benchmarkRequired)
    }
}

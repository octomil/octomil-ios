import Foundation
import XCTest
@testable import Octomil

/// SDK parity tests for the runtime planner.
///
/// These tests verify that the iOS SDK's planner types and behavior match
/// the Python SDK. Specifically:
/// - Policy name constants match across SDKs
/// - Route metadata fields are present and correctly derived
/// - Private policy produces no cloud candidates
/// - Cloud-only policy produces no local candidates
/// - Benchmark submission rejects banned metadata keys
final class RuntimePlannerParityTests: XCTestCase {

    private var tempDir: URL!
    private var store: RuntimePlannerStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "octomil-parity-test-\(UUID().uuidString)",
                isDirectory: true
            )
        store = RuntimePlannerStore(cacheDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Policy Names Match Python SDK

    func testPolicyNamesMatchPythonSDK() {
        // The Python SDK planner accepts these exact string values as
        // routing_policy. The iOS SDK must use identical strings.
        let expectedPolicies: Set<String> = [
            "private",
            "local_only",
            "local_first",
            "cloud_first",
            "cloud_only",
            "performance_first",
        ]

        XCTAssertEqual(
            RuntimeRoutingPolicy.allPolicies, expectedPolicies,
            "Policy names must match the Python SDK exactly"
        )
    }

    func testPolicyConstantValues() {
        XCTAssertEqual(RuntimeRoutingPolicy.private, "private")
        XCTAssertEqual(RuntimeRoutingPolicy.localOnly, "local_only")
        XCTAssertEqual(RuntimeRoutingPolicy.localFirst, "local_first")
        XCTAssertEqual(RuntimeRoutingPolicy.cloudFirst, "cloud_first")
        XCTAssertEqual(RuntimeRoutingPolicy.cloudOnly, "cloud_only")
        XCTAssertEqual(RuntimeRoutingPolicy.performanceFirst, "performance_first")
    }

    func testNoQualityFirstPolicy() {
        // quality_first is intentionally absent across all SDKs.
        XCTAssertFalse(
            RuntimeRoutingPolicy.allPolicies.contains("quality_first"),
            "quality_first must NOT be a valid policy"
        )
    }

    func testContractRoutingPolicyAlignment() {
        // The generated ContractRoutingPolicy enum should include the
        // same values (minus auto which is an SDK-only convenience).
        let contractCases: [ContractRoutingPolicy] = [
            .private, .localOnly, .localFirst, .cloudFirst, .cloudOnly, .performanceFirst,
        ]
        let contractRawValues = Set(contractCases.map { $0.rawValue })

        // Every contract value must be in our policy constants
        for rawValue in contractRawValues {
            XCTAssertTrue(
                RuntimeRoutingPolicy.allPolicies.contains(rawValue),
                "Contract policy '\(rawValue)' missing from RuntimeRoutingPolicy.allPolicies"
            )
        }
    }

    // MARK: - Planner Route Metadata Nested Structure

    func testRouteMetadataNestedFieldsPresent() {
        let model = RouteModel(
            requested: RouteModelRequested(ref: "gemma-2b", kind: "model", capability: "text")
        )
        let metadata = PlannerRouteMetadata(
            status: "selected",
            execution: RouteExecution(locality: "local", mode: "sdk_runtime", engine: "mlx-lm"),
            model: model,
            planner: PlannerInfo(source: "server"),
            fallback: FallbackInfo(used: false),
            reason: RouteReason(code: "server_plan", message: "test reason")
        )

        XCTAssertEqual(metadata.status, "selected")
        XCTAssertEqual(metadata.execution?.locality, "local")
        XCTAssertEqual(metadata.execution?.mode, "sdk_runtime")
        XCTAssertEqual(metadata.execution?.engine, "mlx-lm")
        XCTAssertEqual(metadata.model.requested.ref, "gemma-2b")
        XCTAssertEqual(metadata.model.requested.kind, "model")
        XCTAssertEqual(metadata.model.requested.capability, "text")
        XCTAssertEqual(metadata.planner.source, "server")
        XCTAssertFalse(metadata.fallback.used)
        XCTAssertEqual(metadata.reason.message, "test reason")
        XCTAssertEqual(metadata.reason.code, "server_plan")
    }

    func testRouteMetadataLocalityValues() {
        let localModel = RouteModel(
            requested: RouteModelRequested(ref: "test-model")
        )
        let local = PlannerRouteMetadata(
            execution: RouteExecution(locality: "local", mode: "sdk_runtime"),
            model: localModel,
            planner: PlannerInfo(source: "cache")
        )
        let cloud = PlannerRouteMetadata(
            execution: RouteExecution(locality: "cloud", mode: "hosted_gateway"),
            model: localModel,
            planner: PlannerInfo(source: "server")
        )

        XCTAssertEqual(local.execution?.locality, "local")
        XCTAssertEqual(local.execution?.mode, "sdk_runtime")
        XCTAssertEqual(cloud.execution?.locality, "cloud")
        XCTAssertEqual(cloud.execution?.mode, "hosted_gateway")
    }

    func testRouteMetadataFromLocalSelection() {
        let selection = RuntimeSelection(
            locality: .local,
            engine: "llama.cpp",
            source: "server_plan",
            reason: "best for this device",
            model: "gemma-2b",
            capability: "text"
        )

        let metadata = selection.routeMetadata()

        XCTAssertEqual(metadata.execution?.locality, "local")
        XCTAssertEqual(metadata.execution?.mode, "sdk_runtime")
        XCTAssertEqual(metadata.execution?.engine, "llama.cpp")
        XCTAssertEqual(metadata.model.requested.ref, "gemma-2b")
        XCTAssertEqual(metadata.model.requested.kind, "model")
        XCTAssertEqual(metadata.model.requested.capability, "text")
        XCTAssertEqual(metadata.planner.source, "server",
                       "Internal 'server_plan' must normalize to contract 'server'")
        XCTAssertFalse(metadata.fallback.used)
        XCTAssertEqual(metadata.reason.message, "best for this device")
        XCTAssertEqual(metadata.reason.code, "server_plan")
    }

    func testRouteMetadataFromCloudSelection() {
        let selection = RuntimeSelection(
            locality: .cloud,
            engine: nil,
            source: "fallback",
            reason: "no local engine available -- falling back to cloud",
            model: "llama-8b",
            capability: "text"
        )

        let metadata = selection.routeMetadata()

        XCTAssertEqual(metadata.execution?.locality, "cloud")
        XCTAssertEqual(metadata.execution?.mode, "hosted_gateway")
        XCTAssertNil(metadata.execution?.engine)
        XCTAssertEqual(metadata.planner.source, "offline",
                       "Internal 'fallback' must normalize to contract 'offline'")
        XCTAssertTrue(metadata.fallback.used)
    }

    func testRouteMetadataFromFallbackSelection() {
        let selection = RuntimeSelection(
            locality: .local,
            engine: "mlx-lm",
            source: "cache",
            reason: "fallback: slow but works",
            model: "phi-3",
            capability: "text"
        )

        let metadata = selection.routeMetadata()

        XCTAssertEqual(metadata.execution?.locality, "local")
        XCTAssertEqual(metadata.execution?.mode, "sdk_runtime")
        XCTAssertEqual(metadata.execution?.engine, "mlx-lm")
        XCTAssertEqual(metadata.planner.source, "cache")
        XCTAssertTrue(metadata.fallback.used)
    }

    func testRouteMetadataFromEmptySourceSelection() {
        let selection = RuntimeSelection(locality: .local)

        let metadata = selection.routeMetadata()

        XCTAssertEqual(metadata.planner.source, "offline",
                       "Empty source should map to 'offline'")
    }

    func testRouteMetadataExecutionMode() {
        let localSelection = RuntimeSelection(
            locality: .local,
            engine: "coreml",
            source: "local_default",
            model: "gemma-2b",
            capability: "text"
        )
        let cloudSelection = RuntimeSelection(
            locality: .cloud,
            source: "fallback",
            model: "gemma-2b",
            capability: "text"
        )

        let localMeta = localSelection.routeMetadata()
        let cloudMeta = cloudSelection.routeMetadata()

        XCTAssertEqual(localMeta.execution?.mode, "sdk_runtime",
                       "Local selections must use sdk_runtime mode")
        XCTAssertEqual(cloudMeta.execution?.mode, "hosted_gateway",
                       "Cloud selections must use hosted_gateway mode")
    }

    func testLocalityNeverOnDevice() {
        // "on_device" must NEVER appear as a locality in PlannerRouteMetadata.
        // Public API uses "local" for on-device inference.
        let localSelection = RuntimeSelection(
            locality: .local,
            engine: "mlx-lm",
            source: "server_plan",
            model: "gemma-2b",
            capability: "text"
        )

        let metadata = localSelection.routeMetadata()

        XCTAssertEqual(metadata.execution?.locality, "local",
                       "Locality must be 'local', never 'on_device'")
        XCTAssertNotEqual(metadata.execution?.locality, "on_device",
                          "'on_device' must never appear as a public locality value")
    }

    func testRouteMetadataModelInfo() {
        let selection = RuntimeSelection(
            locality: .local,
            engine: "llama.cpp",
            source: "server_plan",
            reason: "best match",
            model: "phi-3",
            capability: "embeddings"
        )

        let metadata = selection.routeMetadata()

        XCTAssertEqual(metadata.model.requested.ref, "phi-3")
        XCTAssertEqual(metadata.model.requested.kind, "model")
        XCTAssertEqual(metadata.model.requested.capability, "embeddings")
        XCTAssertNil(metadata.model.resolved,
                     "Resolved should be nil when planner does not resolve a specific version")
    }

    func testRouteMetadataEmptyModelKind() {
        // When model is empty, kind should be "unknown"
        let selection = RuntimeSelection(locality: .local)

        let metadata = selection.routeMetadata()

        XCTAssertEqual(metadata.model.requested.kind, "unknown")
        XCTAssertNil(metadata.model.requested.capability)
    }

    // MARK: - Private Policy: No Cloud Candidates

    func testPrivatePolicyNeverProducesCloudLocality() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // Even with no local engines, private must stay local
        let selection = await planner.resolve(
            model: "any-model",
            capability: "text",
            routingPolicy: RuntimeRoutingPolicy.private,
            allowNetwork: true
        )

        XCTAssertEqual(
            selection.locality, .local,
            "Private policy must never produce a cloud selection"
        )

        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.execution?.locality, "local")
        XCTAssertEqual(metadata.execution?.mode, "sdk_runtime")
    }

    func testPrivatePolicyWithLocalEvidenceSelectsLocal() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let evidence = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "phi-3",
            capabilities: ["text"],
            accelerator: "metal"
        )

        let selection = await planner.resolve(
            model: "phi-3",
            capability: "text",
            routingPolicy: RuntimeRoutingPolicy.private,
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .local)
        XCTAssertEqual(selection.engine, "llama.cpp")
        XCTAssertEqual(selection.source, "local_default")
    }

    func testPrivatePolicyRejectsCachedCloudPlan() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let model = "parity-private-cloud-test"

        // Insert a cached plan with a cloud candidate
        let cacheKey = RuntimePlannerStore.makeCacheKey([
            "model": model,
            "capability": "text",
            "policy": "private",
            "sdk_version": OctomilVersion.current,
            "platform": DeviceRuntimeProfileCollector.platformName(),
            "arch": DeviceRuntimeProfileCollector.cpuArchitecture(),
        ])

        let plan = RuntimePlanResponse(
            model: model,
            capability: "text",
            policy: "private",
            candidates: [
                RuntimeCandidatePlan(
                    locality: .cloud,
                    priority: 1,
                    confidence: 0.99,
                    reason: "stale cloud candidate"
                ),
            ]
        )

        store.putPlan(
            cacheKey: cacheKey,
            model: model,
            capability: "text",
            policy: "private",
            plan: plan,
            source: "test"
        )

        let selection = await planner.resolve(
            model: model,
            capability: "text",
            routingPolicy: "private",
            allowNetwork: false
        )

        XCTAssertEqual(selection.locality, .local,
                       "Private policy must reject cached cloud plans")
    }

    // MARK: - Cloud-Only Policy: No Local Candidates

    func testCloudOnlyNeverProducesLocalLocality() async {
        let planner = RuntimePlanner(store: store, client: nil)

        // Provide a fully-capable local engine -- cloud_only must ignore it
        let evidence = InstalledRuntime.modelCapable(
            engine: "mlx",
            model: "gemma-2b",
            capabilities: ["text"],
            accelerator: "metal"
        )

        let selection = await planner.resolve(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: RuntimeRoutingPolicy.cloudOnly,
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(
            selection.locality, .cloud,
            "Cloud-only policy must never produce a local selection"
        )

        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.execution?.locality, "cloud")
        XCTAssertEqual(metadata.execution?.mode, "hosted_gateway")
    }

    func testCloudOnlyIgnoresBenchmarkCache() async {
        let planner = RuntimePlanner(store: store, client: nil)
        let evidence = InstalledRuntime.modelCapable(
            engine: "llama.cpp",
            model: "bench-parity-model",
            capabilities: ["text"]
        )

        // Record a benchmark that would normally cause local selection
        planner.recordBenchmark(
            model: "bench-parity-model",
            capability: "text",
            routingPolicy: "cloud_only",
            result: BenchmarkResult(
                engineName: "llama.cpp",
                tokensPerSecond: 100.0,
                ttftMs: 50.0,
                memoryMb: 256.0
            ),
            additionalRuntimes: [evidence]
        )

        let selection = await planner.resolve(
            model: "bench-parity-model",
            capability: "text",
            routingPolicy: "cloud_only",
            allowNetwork: false,
            additionalRuntimes: [evidence]
        )

        XCTAssertEqual(selection.locality, .cloud,
                       "Cloud-only must ignore benchmark cache")
    }

    // MARK: - Benchmark Submission Rejects Banned Metadata Keys

    func testBenchmarkSubmissionRejectsBannedKeys() {
        let violations = RuntimeBenchmarkSubmission.validateMetadata([
            "prompt": "hello world",
            "selection_source": "planner",
            "file_path": "/tmp/model.gguf",
            "input": "test input",
        ])

        XCTAssertTrue(violations.contains("prompt"))
        XCTAssertTrue(violations.contains("file_path"))
        XCTAssertTrue(violations.contains("input"))
        XCTAssertFalse(violations.contains("selection_source"),
                       "selection_source is not a banned key")
    }

    func testBenchmarkSubmissionStripsPromptKey() {
        let submission = RuntimeBenchmarkSubmission(
            model: "llama-8b",
            capability: "text",
            engine: "mlx-lm",
            success: true,
            tokensPerSecond: 85.0,
            ttftMs: 120.0,
            peakMemoryBytes: 536_870_912,
            metadata: [
                "prompt": "user secret prompt",
                "selection_source": "planner",
                "output": "model response text",
            ]
        )

        XCTAssertNil(submission.metadata["prompt"],
                     "Prompt must be stripped from benchmark metadata")
        XCTAssertNil(submission.metadata["output"],
                     "Output must be stripped from benchmark metadata")
        XCTAssertEqual(submission.metadata["selection_source"], "planner",
                       "Non-banned keys must be preserved")
    }

    func testBenchmarkSubmissionAllBannedKeys() {
        // Verify every banned key is actually rejected
        for key in RuntimeBenchmarkSubmission.bannedKeys {
            let violations = RuntimeBenchmarkSubmission.validateMetadata([key: "test"])
            XCTAssertTrue(
                violations.contains(key),
                "Banned key '\(key)' was not detected by validation"
            )
        }
    }

    func testBenchmarkSubmissionCaseInsensitiveBannedKeys() {
        let violations = RuntimeBenchmarkSubmission.validateMetadata([
            "Prompt": "test",
            "FILE_PATH": "test",
            "User_Id": "test",
        ])

        XCTAssertTrue(violations.contains("prompt"))
        XCTAssertTrue(violations.contains("file_path"))
        XCTAssertTrue(violations.contains("user_id"))
    }

    func testBenchmarkSubmissionToDictionary() {
        let submission = RuntimeBenchmarkSubmission(
            model: "llama-8b",
            capability: "text",
            engine: "mlx",
            success: true,
            tokensPerSecond: 85.0,
            ttftMs: 120.0,
            peakMemoryBytes: 536_870_912,
            metadata: ["selection_source": "benchmark"]
        )

        let dict = submission.toDictionary()

        XCTAssertEqual(dict["model"] as? String, "llama-8b")
        XCTAssertEqual(dict["capability"] as? String, "text")
        XCTAssertEqual(dict["engine"] as? String, "mlx-lm",
                       "Engine should be canonicalized")
        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertEqual(dict["tokens_per_second"] as? Double, 85.0)
        XCTAssertEqual(dict["ttft_ms"] as? Double, 120.0)
        XCTAssertEqual(dict["peak_memory_bytes"] as? Int64, 536_870_912)
        XCTAssertEqual(dict["source"] as? String, "planner")
    }

    func testBenchmarkSubmissionValidMetadataPassesValidation() {
        let violations = RuntimeBenchmarkSubmission.validateMetadata([
            "selection_source": "planner",
            "device_chip": "M2 Pro",
            "engine_version": "0.30.0",
        ])

        XCTAssertTrue(violations.isEmpty,
                       "Valid metadata should have no violations")
    }

    // MARK: - RuntimePlanRequest Type Safety

    func testRuntimePlanRequestCodable() throws {
        let device = DeviceRuntimeProfile(
            sdk: "ios",
            sdkVersion: OctomilVersion.current,
            platform: "iOS",
            arch: "arm64"
        )

        let request = RuntimePlanRequest(
            model: "llama-8b",
            capability: "text",
            routingPolicy: "local_first",
            device: device,
            allowCloudFallback: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model"] as? String, "llama-8b")
        XCTAssertEqual(json["capability"] as? String, "text")
        XCTAssertEqual(json["routing_policy"] as? String, "local_first")
        XCTAssertEqual(json["allow_cloud_fallback"] as? Bool, true)
        XCTAssertNotNil(json["device"])

        // Verify snake_case keys
        XCTAssertNil(json["routingPolicy"])
        XCTAssertNil(json["allowCloudFallback"])
    }

    func testRuntimePlanRequestRoundTrip() throws {
        let device = DeviceRuntimeProfile(
            sdk: "ios",
            sdkVersion: "1.1.0",
            platform: "iOS",
            arch: "arm64",
            osVersion: "18.0",
            chip: "iPhone16,1",
            ramTotalBytes: 8_589_934_592,
            accelerators: ["metal", "ane"],
            installedRuntimes: [
                InstalledRuntime(engine: "coreml", available: true),
            ]
        )

        let request = RuntimePlanRequest(
            model: "gemma-2b",
            capability: "text",
            routingPolicy: "local_first",
            device: device,
            allowCloudFallback: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RuntimePlanRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testRuntimePlanRequestOptionalFields() throws {
        let device = DeviceRuntimeProfile(
            sdk: "ios",
            sdkVersion: OctomilVersion.current,
            platform: "macOS",
            arch: "arm64"
        )

        let request = RuntimePlanRequest(
            model: "llama-8b",
            capability: "text",
            device: device
        )

        XCTAssertNil(request.routingPolicy)
        XCTAssertNil(request.allowCloudFallback)

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Nil optional fields should not be present in JSON
        // (JSONEncoder default behavior encodes nil as null, which is fine
        // for the server to handle)
        XCTAssertEqual(json["model"] as? String, "llama-8b")
    }

    // MARK: - Client Endpoint Paths

    func testClientEndpointPaths() {
        XCTAssertEqual(RuntimePlannerClient.planPath, "/api/v2/runtime/plan")
        XCTAssertEqual(RuntimePlannerClient.benchmarkPath, "/api/v2/runtime/benchmarks")
        XCTAssertEqual(RuntimePlannerClient.defaultsPath, "/api/v2/runtime/defaults")
    }

    // MARK: - Defaults Endpoint

    func testFetchDefaultsReturnsNilOnFailure() async {
        let client = RuntimePlannerClient(
            baseURL: URL(string: "http://localhost:1")!,
            apiKey: "test",
            timeoutSeconds: 1
        )

        let result = await client.fetchDefaults()
        XCTAssertNil(result, "Should return nil on connection failure")
    }

    func testDefaultsResponseDecodable() throws {
        let json = """
        {
            "default_engines": {
                "chat": ["mlx-lm", "llama.cpp"],
                "embeddings": ["onnxruntime"]
            },
            "supported_capabilities": ["chat", "embeddings", "transcription"],
            "supported_policies": ["private", "local_only", "local_first", "cloud_first", "cloud_only", "performance_first"],
            "plan_ttl_seconds": 604800
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(
            RuntimePlannerClient.RuntimeDefaultsResponse.self,
            from: json
        )

        XCTAssertEqual(response.defaultEngines["chat"], ["mlx-lm", "llama.cpp"])
        XCTAssertEqual(response.defaultEngines["embeddings"], ["onnxruntime"])
        XCTAssertEqual(response.supportedCapabilities, ["chat", "embeddings", "transcription"])
        XCTAssertEqual(response.supportedPolicies.count, 6)
        XCTAssertTrue(response.supportedPolicies.contains("private"))
        XCTAssertTrue(response.supportedPolicies.contains("performance_first"))
        XCTAssertFalse(response.supportedPolicies.contains("quality_first"))
        XCTAssertEqual(response.planTtlSeconds, 604_800)
    }

    // MARK: - Engine ID Canonicalization (Cross-SDK Parity)

    func testEngineAliasesMatchPythonSDK() {
        // The Python SDK's _ENGINE_ALIASES dict and the iOS SDK's
        // RuntimeEngineID.aliases dict must produce identical canonical names.
        let testCases: [(alias: String, canonical: String)] = [
            ("mlx", "mlx-lm"),
            ("mlx_lm", "mlx-lm"),
            ("mlxlm", "mlx-lm"),
            ("llamacpp", "llama.cpp"),
            ("llama_cpp", "llama.cpp"),
            ("llama-cpp", "llama.cpp"),
            ("whisper", "whisper.cpp"),
            ("whispercpp", "whisper.cpp"),
            ("whisper_cpp", "whisper.cpp"),
            ("whisper-cpp", "whisper.cpp"),
        ]

        for (alias, expected) in testCases {
            XCTAssertEqual(
                RuntimeEngineID.canonical(alias), expected,
                "Engine alias '\(alias)' should canonicalize to '\(expected)'"
            )
        }
    }

    func testCanonicalEngineIdPreservesUnknownEngines() {
        XCTAssertEqual(RuntimeEngineID.canonical("coreml"), "coreml")
        XCTAssertEqual(RuntimeEngineID.canonical("onnxruntime"), "onnxruntime")
        XCTAssertEqual(RuntimeEngineID.canonical("custom-engine"), "custom-engine")
    }

    func testCanonicalEngineIdHandlesNil() {
        let result: String? = RuntimeEngineID.canonical(nil as String?)
        XCTAssertNil(result)
    }

    // MARK: - RuntimeLocality Wire Format

    func testRuntimeLocalityWireFormat() throws {
        let encoder = JSONEncoder()

        let localData = try encoder.encode(RuntimeLocality.local)
        let cloudData = try encoder.encode(RuntimeLocality.cloud)

        XCTAssertEqual(String(data: localData, encoding: .utf8), "\"local\"")
        XCTAssertEqual(String(data: cloudData, encoding: .utf8), "\"cloud\"")
    }

    // MARK: - Contract Fixture: RuntimeDefaultsResponse

    func testDecodeContractFixtureRuntimeDefaults() throws {
        // Decode a vendored copy of the contract fixture (originally from
        // octomil-contracts/fixtures/runtime_planner/runtime_defaults.json).
        // Vendored into the test bundle so CI does not need a sibling checkout.
        let fixturePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Planner/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("runtime_defaults.json")

        let fixtureData = try Data(contentsOf: fixturePath)
        // The fixture wraps the response under a "response" key.
        let wrapper = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
        let responseDict = wrapper["response"] as! [String: Any]
        let responseData = try JSONSerialization.data(withJSONObject: responseDict)

        let decoder = JSONDecoder()
        let response = try decoder.decode(
            RuntimePlannerClient.RuntimeDefaultsResponse.self,
            from: responseData
        )

        // Validate all required contract fields decode correctly.
        XCTAssertFalse(response.defaultEngines.isEmpty,
                       "default_engines must not be empty")
        XCTAssertEqual(response.defaultEngines["chat"], ["mlx-lm", "llama.cpp"])
        XCTAssertEqual(response.defaultEngines["responses"], ["mlx-lm", "llama.cpp"])
        XCTAssertEqual(response.defaultEngines["embeddings"], ["onnxruntime"])
        XCTAssertEqual(response.defaultEngines["transcription"], ["whisper.cpp"])
        XCTAssertEqual(response.defaultEngines["audio"], ["whisper.cpp"])

        XCTAssertEqual(response.supportedCapabilities,
                       ["chat", "responses", "embeddings", "transcription", "audio"])

        XCTAssertEqual(response.supportedPolicies,
                       ["private", "local_only", "local_first", "cloud_first",
                        "cloud_only", "performance_first", "auto"])

        XCTAssertEqual(response.planTtlSeconds, 604_800)
    }

    // MARK: - Planner Source Normalization (Contract Enum)

    func testPlannerSourceNormalizationServerPlan() {
        let selection = RuntimeSelection(
            locality: .local, engine: "mlx-lm", source: "server_plan",
            model: "gemma-2b", capability: "chat"
        )
        XCTAssertEqual(selection.routeMetadata().planner.source, "server",
                       "'server_plan' must normalize to 'server'")
    }

    func testPlannerSourceNormalizationCache() {
        let selection = RuntimeSelection(
            locality: .local, engine: "mlx-lm", source: "cache",
            model: "gemma-2b", capability: "chat"
        )
        XCTAssertEqual(selection.routeMetadata().planner.source, "cache",
                       "'cache' must pass through as 'cache'")
    }

    func testPlannerSourceNormalizationLocalDefault() {
        let selection = RuntimeSelection(
            locality: .local, engine: "coreml", source: "local_default",
            model: "gemma-2b", capability: "chat"
        )
        XCTAssertEqual(selection.routeMetadata().planner.source, "offline",
                       "'local_default' must normalize to 'offline'")
    }

    func testPlannerSourceNormalizationFallback() {
        let selection = RuntimeSelection(
            locality: .cloud, source: "fallback",
            model: "llama-8b", capability: "chat"
        )
        XCTAssertEqual(selection.routeMetadata().planner.source, "offline",
                       "'fallback' must normalize to 'offline'")
    }

    func testPlannerSourceNormalizationEmpty() {
        let selection = RuntimeSelection(locality: .local, source: "",
                                         model: "gemma-2b", capability: "chat")
        XCTAssertEqual(selection.routeMetadata().planner.source, "offline",
                       "Empty source must normalize to 'offline'")
    }

    func testPlannerSourceOnlyProducesContractValues() {
        // Exhaustive check: every internal source string must map to one of
        // the three contract-allowed values.
        let contractAllowed: Set<String> = ["server", "cache", "offline"]
        let internalSources = ["server_plan", "cache", "local_default", "fallback", "empty", ""]

        for src in internalSources {
            let selection = RuntimeSelection(
                locality: .local, source: src, model: "test", capability: "chat"
            )
            let produced = selection.routeMetadata().planner.source
            XCTAssertTrue(contractAllowed.contains(produced),
                          "Source '\(src)' produced '\(produced)' which is not in contract enum \(contractAllowed)")
        }
    }
}

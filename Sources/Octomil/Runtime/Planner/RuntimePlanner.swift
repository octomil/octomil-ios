import Foundation
import CommonCrypto
import os.log

/// Resolves the best engine/locality for a given model and capability.
///
/// Resolution order:
/// 1. Collect device profile
/// 2. Check local plan cache
/// 3. If network allowed and not private policy, fetch server plan
/// 4. Validate server plan against installed native runtimes
/// 5. Check real local benchmark cache
/// 6. Select an explicitly reported local runtime, if one exists
/// 7. Return ``RuntimeSelection``
///
/// The planner never blocks inference on server failures. All network
/// operations are best-effort with short timeouts.
///
/// **Privacy guarantees:**
/// - No prompts, responses, file paths, or user input in telemetry
/// - Private policy skips server plan fetch and telemetry upload
/// - Cloud-only policy skips local benchmarking
public final class RuntimePlanner: @unchecked Sendable {

    // MARK: - Properties

    private let store: RuntimePlannerStore
    private let client: RuntimePlannerClient?
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "RuntimePlanner")

    // MARK: - Initialization

    /// Creates a new runtime planner.
    ///
    /// - Parameters:
    ///   - store: Local cache for plans and benchmarks.
    ///   - client: Optional HTTP client for server plan fetch. Pass `nil` for
    ///     fully-offline operation.
    public init(
        store: RuntimePlannerStore = RuntimePlannerStore(),
        client: RuntimePlannerClient? = nil
    ) {
        self.store = store
        self.client = client
    }

    // MARK: - Resolve

    /// Resolve the best runtime for the given model and capability.
    ///
    /// This is the main entry point. It coordinates profile collection,
    /// cache lookup, server plan fetch, plan validation, and benchmark
    /// execution to produce a single ``RuntimeSelection``.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "gemma-2b", "llama-8b").
    ///   - capability: The needed capability (e.g. "text", "embeddings", "audio").
    ///   - routingPolicy: One of "local_first", "cloud_first", "local_only",
    ///     "cloud_only", "private". Defaults to "local_first".
    ///   - allowNetwork: Whether to contact the server. Set to `false` for
    ///     fully-offline operation.
    ///   - additionalRuntimes: Extra runtimes detected by extension modules
    ///     (e.g. MLX, llama.cpp) not visible to the core SDK.
    /// - Returns: The resolved ``RuntimeSelection``.
    public func resolve(
        model: String,
        capability: String,
        routingPolicy: String = "local_first",
        allowNetwork: Bool = true,
        additionalRuntimes: [InstalledRuntime] = []
    ) async -> RuntimeSelection {

        // Step 1: Collect device profile
        let device = DeviceRuntimeProfileCollector.collect(additionalRuntimes: additionalRuntimes)

        // Step 2: Check local plan cache
        let cacheKey = RuntimePlannerStore.makeCacheKey([
            "model": model,
            "capability": capability,
            "policy": routingPolicy,
            "sdk_version": OctomilVersion.current,
            "platform": device.platform,
            "arch": device.arch,
        ])

        if let cachedPlan = store.getPlan(cacheKey: cacheKey) {
            logger.debug("Using cached plan for \(model)/\(capability)")
            if let selection = resolveFromServerPlan(cachedPlan, device: device, source: "cache") {
                return selection
            }
            logger.debug("Cached plan had no viable candidates; continuing resolution")
        }

        // Step 3: Fetch server plan if allowed
        let isPrivate = routingPolicy == "private"
        var serverPlan: RuntimePlanResponse?

        if allowNetwork && client != nil && !isPrivate {
            serverPlan = await client?.fetchPlan(
                model: model,
                capability: capability,
                routingPolicy: routingPolicy,
                device: device,
                allowCloudFallback: routingPolicy != "local_only"
            )

            if let plan = serverPlan {
                logger.debug("Received server plan for \(model)/\(capability)")
                // Cache it
                store.putPlan(
                    cacheKey: cacheKey,
                    model: model,
                    capability: capability,
                    policy: routingPolicy,
                    plan: plan,
                    source: "server_plan"
                )
            }
        }

        // Step 4: Validate server plan against installed runtimes
        if let plan = serverPlan {
            if let selection = resolveFromServerPlan(plan, device: device, source: "server_plan") {
                return selection
            }
        }

        // Steps 5-8: Fall back to local engine selection
        return resolveLocally(
            model: model,
            capability: capability,
            routingPolicy: routingPolicy,
            device: device,
            isPrivate: isPrivate
        )
    }

    // MARK: - Server Plan Resolution

    /// Try to select a runtime from a server plan.
    ///
    /// Validates each candidate against locally installed engines.
    /// Cloud candidates are accepted as-is.
    private func resolveFromServerPlan(
        _ plan: RuntimePlanResponse,
        device: DeviceRuntimeProfile,
        source: String
    ) -> RuntimeSelection? {
        let installedEngines = Set(
            device.installedRuntimes
                .filter { $0.available }
                .map { RuntimeEngineID.canonical($0.engine) }
        )

        if let selection = selectCandidate(
            from: plan.candidates,
            installedEngines: installedEngines,
            source: source,
            fallbackCandidates: plan.fallbackCandidates,
            fallbackPrefix: nil
        ) {
            return selection
        }

        return selectCandidate(
            from: plan.fallbackCandidates,
            installedEngines: installedEngines,
            source: source,
            fallbackCandidates: [],
            fallbackPrefix: "fallback: "
        )
    }

    private func selectCandidate(
        from candidates: [RuntimeCandidatePlan],
        installedEngines: Set<String>,
        source: String,
        fallbackCandidates: [RuntimeCandidatePlan],
        fallbackPrefix: String?
    ) -> RuntimeSelection? {
        for candidate in candidates {
            switch candidate.locality {
            case .local:
                let engine = RuntimeEngineID.canonical(candidate.engine)
                if let engine {
                    if !installedEngines.contains(engine) {
                        continue // Skip engines we don't have
                    }
                } else if installedEngines.isEmpty {
                    continue // "any local" still requires at least one runtime
                }
                return RuntimeSelection(
                    locality: .local,
                    engine: engine,
                    artifact: candidate.artifact,
                    benchmarkRan: false,
                    source: source,
                    fallbackCandidates: fallbackCandidates,
                    reason: "\(fallbackPrefix ?? "")\(candidate.reason)"
                )
            case .cloud:
                return RuntimeSelection(
                    locality: .cloud,
                    engine: RuntimeEngineID.canonical(candidate.engine),
                    artifact: candidate.artifact,
                    benchmarkRan: false,
                    source: source,
                    fallbackCandidates: fallbackCandidates,
                    reason: "\(fallbackPrefix ?? "")\(candidate.reason)"
                )
            }
        }

        return nil
    }

    // MARK: - Local Resolution

    /// Resolve using local engine detection and benchmark cache.
    private func resolveLocally(
        model: String,
        capability: String,
        routingPolicy: String,
        device: DeviceRuntimeProfile,
        isPrivate: Bool
    ) -> RuntimeSelection {
        // For cloud_only policy, skip local work entirely
        if routingPolicy == "cloud_only" {
            return RuntimeSelection(
                locality: .cloud,
                engine: nil,
                source: "fallback",
                reason: "cloud_only policy -- no local engines attempted"
            )
        }

        // Step 5: Check local benchmark cache
        let bmCacheKey = benchmarkCacheKey(
            model: model,
            capability: capability,
            policy: routingPolicy,
            device: device
        )

        if let cached = store.getBenchmark(cacheKey: bmCacheKey) {
            let engine = RuntimeEngineID.canonical(cached.engine)
            return RuntimeSelection(
                locality: .local,
                engine: engine,
                benchmarkRan: false,
                source: "cache",
                reason: "cached benchmark: \(String(format: "%.1f", cached.tokensPerSecond)) tok/s"
            )
        }

        // Step 6: Determine best available local engine.
        // The core SDK cannot directly run benchmarks (that requires engine
        // binaries from extension modules). Without a server plan, only use
        // runtimes that explicitly declare support for this model/capability.
        let availableEngines = device.installedRuntimes.filter {
            supportsLocalDefault($0, model: model, capability: capability)
        }

        if let bestEngine = availableEngines.first {
            let engine = RuntimeEngineID.canonical(bestEngine.engine)
            return RuntimeSelection(
                locality: .local,
                engine: engine,
                benchmarkRan: false,
                source: "local_default",
                reason: "selected explicitly reported local engine: \(engine)"
            )
        }

        // No local engine available
        if routingPolicy == "local_only" || isPrivate {
            return RuntimeSelection(
                locality: .local,
                engine: nil,
                source: "fallback",
                reason: "no local engine available"
            )
        }

        return RuntimeSelection(
            locality: .cloud,
            engine: nil,
            source: "fallback",
            reason: "no local engine available -- falling back to cloud"
        )
    }

    // MARK: - Benchmark Reporting

    /// Store a benchmark result that was collected during actual inference.
    ///
    /// Call this after the first inference run to record real performance
    /// metrics. The planner never writes synthetic benchmark entries during
    /// resolution; only real engine runs should call this method.
    ///
    /// - Parameters:
    ///   - model: Model identifier.
    ///   - capability: Capability string.
    ///   - routingPolicy: Routing policy used.
    ///   - result: The benchmark result.
    ///   - additionalRuntimes: Extra runtimes for profile collection.
    public func recordBenchmark(
        model: String,
        capability: String,
        routingPolicy: String = "local_first",
        result: BenchmarkResult,
        additionalRuntimes: [InstalledRuntime] = []
    ) {
        let device = DeviceRuntimeProfileCollector.collect(additionalRuntimes: additionalRuntimes)
        let bmCacheKey = benchmarkCacheKey(
            model: model,
            capability: capability,
            policy: routingPolicy,
            device: device
        )

        store.putBenchmark(
            cacheKey: bmCacheKey,
            model: model,
            capability: capability,
            engine: RuntimeEngineID.canonical(result.engineName),
            policy: routingPolicy,
            tokensPerSecond: result.tokensPerSecond,
            ttftMs: result.ttftMs,
            memoryMb: result.memoryMb
        )

        // Upload telemetry for non-private policies
        if routingPolicy != "private", let client {
            Task {
                let payload: [String: Any] = [
                    "source": "planner",
                    "model": model,
                    "capability": capability,
                    "engine": RuntimeEngineID.canonical(result.engineName),
                    "device": privacySafeDeviceDict(device),
                    "success": result.ok,
                    "tokens_per_second": result.tokensPerSecond,
                    "ttft_ms": result.ttftMs,
                    "peak_memory_bytes": Int(result.memoryMb * 1024 * 1024),
                    "metadata": ["selection_source": "benchmark"],
                ]
                _ = await client.uploadBenchmark(payload)
            }
        }
    }

    // MARK: - Helpers

    private func benchmarkCacheKey(
        model: String,
        capability: String,
        policy: String,
        device: DeviceRuntimeProfile
    ) -> String {
        RuntimePlannerStore.makeCacheKey([
            "model": model,
            "capability": capability,
            "policy": policy,
            "sdk_version": device.sdkVersion,
            "platform": device.platform,
            "arch": device.arch,
            "chip": device.chip,
            "installed_hash": installedRuntimesHash(device),
        ])
    }

    private func supportsLocalDefault(
        _ runtime: InstalledRuntime,
        model: String,
        capability: String
    ) -> Bool {
        guard runtime.available else { return false }

        let supportedModels = metadataList(runtime.metadata, keys: ["model", "model_id", "models"])
        guard supportedModels.contains("*") || supportedModels.contains(model.lowercased()) else {
            return false
        }

        let supportedCapabilities = metadataList(runtime.metadata, keys: ["capability", "capabilities"])
        return supportedCapabilities.isEmpty
            || supportedCapabilities.contains("*")
            || supportedCapabilities.contains(capability.lowercased())
    }

    private func metadataList(_ metadata: [String: String], keys: [String]) -> Set<String> {
        Set(
            keys
                .compactMap { metadata[$0] }
                .flatMap { value in
                    value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                }
                .filter { !$0.isEmpty }
        )
    }

    private func installedRuntimesHash(_ device: DeviceRuntimeProfile) -> String {
        let runtimes = device.installedRuntimes
            .filter { $0.available }
            .map { "\(RuntimeEngineID.canonical($0.engine)):\($0.version ?? "")" }
            .sorted()
            .joined(separator: ",")

        let data = Data(runtimes.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// Build a privacy-safe device dictionary for telemetry upload.
    ///
    /// Intentionally excludes: user IDs, file paths, prompts, responses,
    /// IP addresses, and any data that could identify a specific user.
    /// Only hardware/software profile metadata is included.
    private func privacySafeDeviceDict(_ device: DeviceRuntimeProfile) -> [String: Any] {
        var dict: [String: Any] = [
            "sdk": device.sdk,
            "sdk_version": device.sdkVersion,
            "platform": device.platform,
            "arch": device.arch,
            "accelerators": device.accelerators,
        ]
        if let osVersion = device.osVersion {
            dict["os_version"] = osVersion
        }
        if let chip = device.chip {
            dict["chip"] = chip
        }
        if let ram = device.ramTotalBytes {
            dict["ram_total_bytes"] = ram
        }
        if let gpuCores = device.gpuCoreCount {
            dict["gpu_core_count"] = gpuCores
        }
        dict["installed_runtimes"] = device.installedRuntimes.map { runtime -> [String: Any] in
            var entry: [String: Any] = [
                "engine": runtime.engine,
                "available": runtime.available,
            ]
            if let version = runtime.version {
                entry["version"] = version
            }
            if let accel = runtime.accelerator {
                entry["accelerator"] = accel
            }
            return entry
        }
        return dict
    }
}

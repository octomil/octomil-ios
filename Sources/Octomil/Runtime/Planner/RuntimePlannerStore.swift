import Foundation
import os.log
import CommonCrypto

/// Local file-based cache for runtime plans and benchmark results.
///
/// Uses JSON files in the app's caches directory. Plans and benchmarks are
/// keyed by a deterministic hash of their parameters and have a configurable TTL.
///
/// This is the iOS equivalent of the Python `RuntimePlannerStore` but uses
/// file-based storage instead of SQLite, which is simpler and sufficient for
/// the small number of entries a mobile device will cache.
public final class RuntimePlannerStore: @unchecked Sendable {

    // MARK: - Types

    struct CachedPlan: Codable {
        let cacheKey: String
        let model: String
        let capability: String
        let policy: String
        let planJson: Data
        let source: String
        let ttlSeconds: Int
        let createdAt: Date
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case cacheKey = "cache_key"
            case model, capability, policy
            case planJson = "plan_json"
            case source
            case ttlSeconds = "ttl_seconds"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }
    }

    struct CachedBenchmark: Codable {
        let cacheKey: String
        let model: String
        let capability: String
        let engine: String
        let policy: String
        let tokensPerSecond: Double
        let ttftMs: Double
        let memoryMb: Double
        let createdAt: Date
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case cacheKey = "cache_key"
            case model, capability, engine, policy
            case tokensPerSecond = "tokens_per_second"
            case ttftMs = "ttft_ms"
            case memoryMb = "memory_mb"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }
    }

    struct PlanCacheFile: Codable {
        var entries: [String: CachedPlan]
    }

    struct BenchmarkCacheFile: Codable {
        var entries: [String: CachedBenchmark]
    }

    // MARK: - Properties

    private let planCacheURL: URL
    private let benchmarkCacheURL: URL
    private let lock = NSLock()
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "RuntimePlannerStore")
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    // MARK: - Initialization

    /// Creates a new planner store.
    ///
    /// - Parameter cacheDirectory: Directory for cache files. Defaults to the app's
    ///   caches directory under `octomil/planner/`.
    public init(cacheDirectory: URL? = nil) {
        let baseDir: URL
        if let cacheDirectory {
            baseDir = cacheDirectory
        } else {
            let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            baseDir = cacheRoot.appendingPathComponent("octomil/planner", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        self.planCacheURL = baseDir.appendingPathComponent("plans.json")
        self.benchmarkCacheURL = baseDir.appendingPathComponent("benchmarks.json")

        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .secondsSince1970

        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .secondsSince1970
    }

    // MARK: - Cache Key

    /// Build a deterministic cache key from components.
    ///
    /// Matches the Python `_make_cache_key` logic: sorts key-value pairs,
    /// joins with `|`, and takes the first 32 hex chars of SHA-256.
    public static func makeCacheKey(_ components: [String: String?]) -> String {
        let parts = components
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value ?? "")" }
            .joined(separator: "|")

        let data = Data(parts.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }

    // MARK: - Plan Cache

    /// Retrieve a cached plan if it exists and has not expired.
    ///
    /// - Parameter cacheKey: The deterministic cache key.
    /// - Returns: Decoded ``RuntimePlanResponse``, or `nil` if not cached or expired.
    public func getPlan(cacheKey: String) -> RuntimePlanResponse? {
        lock.lock()
        defer { lock.unlock() }

        let file = loadPlanCache()
        guard let entry = file.entries[cacheKey] else { return nil }

        if Date() > entry.expiresAt {
            // Expired — remove it
            var mutable = file
            mutable.entries.removeValue(forKey: cacheKey)
            savePlanCache(mutable)
            return nil
        }

        do {
            return try jsonDecoder.decode(RuntimePlanResponse.self, from: entry.planJson)
        } catch {
            logger.warning("Failed to decode cached plan: \(error.localizedDescription)")
            return nil
        }
    }

    /// Store a plan in the cache.
    ///
    /// - Parameters:
    ///   - cacheKey: The deterministic cache key.
    ///   - model: Model identifier.
    ///   - capability: Capability string.
    ///   - policy: Routing policy string.
    ///   - plan: The plan response to cache.
    ///   - source: How the plan was obtained (e.g. "server_plan").
    public func putPlan(
        cacheKey: String,
        model: String,
        capability: String,
        policy: String,
        plan: RuntimePlanResponse,
        source: String
    ) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let planData = try jsonEncoder.encode(plan)
            let now = Date()
            let entry = CachedPlan(
                cacheKey: cacheKey,
                model: model,
                capability: capability,
                policy: policy,
                planJson: planData,
                source: source,
                ttlSeconds: plan.planTtlSeconds,
                createdAt: now,
                expiresAt: now.addingTimeInterval(TimeInterval(plan.planTtlSeconds))
            )

            var file = loadPlanCache()
            file.entries[cacheKey] = entry
            savePlanCache(file)
        } catch {
            logger.warning("Failed to cache plan: \(error.localizedDescription)")
        }
    }

    // MARK: - Benchmark Cache

    /// Retrieve a cached benchmark if it exists and has not expired.
    ///
    /// - Parameter cacheKey: The deterministic cache key.
    /// - Returns: Cached benchmark entry, or `nil` if not cached or expired.
    public func getBenchmark(cacheKey: String) -> CachedBenchmark? {
        lock.lock()
        defer { lock.unlock() }

        let file = loadBenchmarkCache()
        guard let entry = file.entries[cacheKey] else { return nil }

        if Date() > entry.expiresAt {
            var mutable = file
            mutable.entries.removeValue(forKey: cacheKey)
            saveBenchmarkCache(mutable)
            return nil
        }

        return entry
    }

    /// Store a benchmark result in the cache.
    ///
    /// - Parameters:
    ///   - cacheKey: The deterministic cache key.
    ///   - model: Model identifier.
    ///   - capability: Capability string.
    ///   - engine: Engine name.
    ///   - policy: Routing policy.
    ///   - tokensPerSecond: Benchmark tokens/sec.
    ///   - ttftMs: Time to first token in ms.
    ///   - memoryMb: Peak memory in MB.
    ///   - ttlSeconds: Cache validity in seconds (default: 14 days).
    public func putBenchmark(
        cacheKey: String,
        model: String,
        capability: String,
        engine: String,
        policy: String = "",
        tokensPerSecond: Double = 0.0,
        ttftMs: Double = 0.0,
        memoryMb: Double = 0.0,
        ttlSeconds: Int = 1_209_600
    ) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let entry = CachedBenchmark(
            cacheKey: cacheKey,
            model: model,
            capability: capability,
            engine: engine,
            policy: policy,
            tokensPerSecond: tokensPerSecond,
            ttftMs: ttftMs,
            memoryMb: memoryMb,
            createdAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(ttlSeconds))
        )

        var file = loadBenchmarkCache()
        file.entries[cacheKey] = entry
        saveBenchmarkCache(file)
    }

    // MARK: - Clear

    /// Remove all cached plans and benchmarks.
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }

        try? FileManager.default.removeItem(at: planCacheURL)
        try? FileManager.default.removeItem(at: benchmarkCacheURL)
    }

    // MARK: - Private I/O

    private func loadPlanCache() -> PlanCacheFile {
        guard let data = try? Data(contentsOf: planCacheURL),
              let file = try? jsonDecoder.decode(PlanCacheFile.self, from: data) else {
            return PlanCacheFile(entries: [:])
        }
        return file
    }

    private func savePlanCache(_ file: PlanCacheFile) {
        do {
            let data = try jsonEncoder.encode(file)
            try data.write(to: planCacheURL, options: .atomic)
        } catch {
            logger.warning("Failed to write plan cache: \(error.localizedDescription)")
        }
    }

    private func loadBenchmarkCache() -> BenchmarkCacheFile {
        guard let data = try? Data(contentsOf: benchmarkCacheURL),
              let file = try? jsonDecoder.decode(BenchmarkCacheFile.self, from: data) else {
            return BenchmarkCacheFile(entries: [:])
        }
        return file
    }

    private func saveBenchmarkCache(_ file: BenchmarkCacheFile) {
        do {
            let data = try jsonEncoder.encode(file)
            try data.write(to: benchmarkCacheURL, options: .atomic)
        } catch {
            logger.warning("Failed to write benchmark cache: \(error.localizedDescription)")
        }
    }
}

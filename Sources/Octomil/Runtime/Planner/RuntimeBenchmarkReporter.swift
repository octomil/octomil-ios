import Foundation
import os.log

/// Singleton relay for recording real benchmark results from engine modules.
///
/// Engine modules (OctomilMLX, OctomilRuntimeLlama, etc.) call
/// ``report(...)`` after a successful local inference run. The reporter
/// delegates to the active ``RuntimePlanner`` if one has been set.
///
/// This avoids threading planner references through every engine constructor
/// while still ensuring real metrics flow into the planner's benchmark cache.
///
/// **Privacy guarantees:**
/// - Private policy: benchmark is stored locally but NOT uploaded
/// - No prompts, responses, or user data in the benchmark payload
public final class RuntimeBenchmarkReporter: @unchecked Sendable {

    /// Shared singleton instance.
    public static let shared = RuntimeBenchmarkReporter()

    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "BenchmarkReporter")
    private let lock = NSLock()
    private var _planner: RuntimePlanner?
    private var _routingPolicy: String = "local_first"

    private init() {}

    // MARK: - Configuration

    /// Set the planner that benchmark results should be recorded to.
    ///
    /// Call this once during SDK initialization. Engine modules do not need
    /// to call this — the umbrella ``OctomilClient`` bootstrap handles it.
    ///
    /// - Parameters:
    ///   - planner: The active runtime planner.
    ///   - routingPolicy: Default routing policy for benchmark recording.
    public func configure(planner: RuntimePlanner, routingPolicy: String = "local_first") {
        lock.lock()
        defer { lock.unlock() }
        _planner = planner
        _routingPolicy = routingPolicy
    }

    // MARK: - Reporting

    /// Report a real benchmark result from a successful inference run.
    ///
    /// This should only be called after actual inference has completed
    /// successfully with real metrics. Do NOT call with synthetic or
    /// placeholder data.
    ///
    /// - Parameters:
    ///   - model: Model identifier.
    ///   - capability: Capability string (e.g. "text", "audio_transcription").
    ///   - engineName: Engine that produced the result.
    ///   - tokensPerSecond: Tokens per second (use 0 for non-token modalities).
    ///   - ttftMs: Time to first token/chunk in milliseconds.
    ///   - memoryMb: Peak memory usage in megabytes (estimate if exact is unavailable).
    ///   - additionalRuntimes: Extra runtimes for device profile (usually empty).
    public func report(
        model: String,
        capability: String,
        engineName: String,
        tokensPerSecond: Double,
        ttftMs: Double,
        memoryMb: Double,
        additionalRuntimes: [InstalledRuntime] = []
    ) {
        lock.lock()
        let planner = _planner
        let policy = _routingPolicy
        lock.unlock()

        guard let planner else {
            logger.debug("No planner configured; dropping benchmark for \(model)/\(capability)")
            return
        }

        let result = BenchmarkResult(
            engineName: engineName,
            tokensPerSecond: tokensPerSecond,
            ttftMs: ttftMs,
            memoryMb: memoryMb
        )

        planner.recordBenchmark(
            model: model,
            capability: capability,
            routingPolicy: policy,
            result: result,
            additionalRuntimes: additionalRuntimes
        )

        logger.debug("Recorded benchmark for \(model)/\(capability): \(String(format: "%.1f", tokensPerSecond)) tok/s")
    }

    /// Reset the reporter. Primarily for testing.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _planner = nil
        _routingPolicy = "local_first"
    }
}

import Foundation
import os.log

// MARK: - AttemptStage

/// Stage at which an attempt resolved (succeeded or failed).
///
/// Matches `route_attempt.schema.json` stage enum from octomil-contracts.
public enum AttemptStage: String, Codable, Sendable, Equatable {
    case policy
    case prepare
    case download
    case verify
    case load
    case benchmark
    case gate
    case inference
}

// MARK: - AttemptStatus

/// Outcome of a single candidate attempt.
///
/// Matches `route_attempt.schema.json` status enum from octomil-contracts.
public enum AttemptStatus: String, Codable, Sendable, Equatable {
    case skipped
    case failed
    case selected
}

// MARK: - GateStatus

/// Outcome of evaluating a single gate.
///
/// Matches `GateResult.status` in `route_attempt.schema.json`.
public enum GateStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case unknown
    case notRequired = "not_required"
}

// MARK: - GateCode

/// The 12 canonical gate codes defined in `candidate_gate.schema.json`.
///
/// SDKs evaluate these gates per-request before selecting a candidate.
public enum GateCode: String, Codable, Sendable, CaseIterable {
    case artifactVerified = "artifact_verified"
    case runtimeAvailable = "runtime_available"
    case modelLoads = "model_loads"
    case contextFits = "context_fits"
    case modalitySupported = "modality_supported"
    case toolSupport = "tool_support"
    case minTokensPerSecond = "min_tokens_per_second"
    case maxTtftMs = "max_ttft_ms"
    case maxErrorRate = "max_error_rate"
    case minFreeMemoryBytes = "min_free_memory_bytes"
    case minFreeStorageBytes = "min_free_storage_bytes"
    case benchmarkFresh = "benchmark_fresh"
}

// MARK: - GateResult

/// Result of evaluating one gate against a candidate.
///
/// Matches the `GateResult` definition in `route_attempt.schema.json`.
public struct GateResult: Codable, Sendable, Equatable {
    public let code: String
    public let status: GateStatus
    public var observedNumber: Double?
    public var thresholdNumber: Double?
    public var reasonCode: String?

    enum CodingKeys: String, CodingKey {
        case code, status
        case observedNumber = "observed_number"
        case thresholdNumber = "threshold_number"
        case reasonCode = "reason_code"
    }

    public init(
        code: String,
        status: GateStatus,
        observedNumber: Double? = nil,
        thresholdNumber: Double? = nil,
        reasonCode: String? = nil
    ) {
        self.code = code
        self.status = status
        self.observedNumber = observedNumber
        self.thresholdNumber = thresholdNumber
        self.reasonCode = reasonCode
    }
}

// MARK: - CandidateGate

/// A gate requirement attached to a candidate by the planner.
///
/// Matches `candidate_gate.schema.json` from octomil-contracts.
/// SDKs evaluate gates per-request before selecting a candidate.
public struct CandidateGate: Codable, Sendable, Equatable {
    public let code: String
    public let required: Bool
    public var thresholdNumber: Double?
    public var thresholdString: String?
    public var windowSeconds: Int?
    public let source: String

    enum CodingKeys: String, CodingKey {
        case code, required, source
        case thresholdNumber = "threshold_number"
        case thresholdString = "threshold_string"
        case windowSeconds = "window_seconds"
    }

    public init(
        code: String,
        required: Bool = true,
        thresholdNumber: Double? = nil,
        thresholdString: String? = nil,
        windowSeconds: Int? = nil,
        source: String = "server"
    ) {
        self.code = code
        self.required = required
        self.thresholdNumber = thresholdNumber
        self.thresholdString = thresholdString
        self.windowSeconds = windowSeconds
        self.source = source
    }
}

// MARK: - AttemptArtifact

/// Artifact state at time of an attempt.
///
/// Matches the `AttemptArtifact` definition in `route_attempt.schema.json`.
public struct AttemptArtifact: Codable, Sendable, Equatable {
    public let id: String?
    public let digest: String?
    public let cache: CacheInfo

    public struct CacheInfo: Codable, Sendable, Equatable {
        /// Cache status: "hit", "miss", "downloaded", "not_applicable", "unavailable".
        public let status: String
        /// Who manages the cache: "octomil", "runtime", "external".
        public let managedBy: String?

        enum CodingKeys: String, CodingKey {
            case status
            case managedBy = "managed_by"
        }

        public init(status: String = "not_applicable", managedBy: String? = nil) {
            self.status = status
            self.managedBy = managedBy
        }
    }

    public init(id: String? = nil, digest: String? = nil, cache: CacheInfo = CacheInfo()) {
        self.id = id
        self.digest = digest
        self.cache = cache
    }
}

// MARK: - AttemptReason

/// Machine-readable code and human-readable message explaining an attempt outcome.
public struct AttemptReason: Codable, Sendable, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - RouteAttempt

/// A single attempt record in the per-request candidate loop.
///
/// Matches `route_attempt.schema.json` from octomil-contracts.
public struct RouteAttempt: Codable, Sendable, Equatable {
    public let index: Int
    public let locality: String
    public let mode: String
    public let engine: String?
    public let artifact: AttemptArtifact?
    public let status: AttemptStatus
    public let stage: AttemptStage
    public let gateResults: [GateResult]
    public let reason: AttemptReason

    enum CodingKeys: String, CodingKey {
        case index, locality, mode, engine, artifact, status, stage, reason
        case gateResults = "gate_results"
    }

    public init(
        index: Int,
        locality: String,
        mode: String,
        engine: String? = nil,
        artifact: AttemptArtifact? = nil,
        status: AttemptStatus,
        stage: AttemptStage,
        gateResults: [GateResult] = [],
        reason: AttemptReason
    ) {
        self.index = index
        self.locality = locality
        self.mode = mode
        self.engine = engine
        self.artifact = artifact
        self.status = status
        self.stage = stage
        self.gateResults = gateResults
        self.reason = reason
    }
}

// MARK: - FallbackTrigger

/// Describes what triggered the fallback from one candidate to another.
public struct FallbackTrigger: Codable, Sendable, Equatable {
    public let code: String
    public let stage: String
    public let message: String

    public init(code: String, stage: String, message: String) {
        self.code = code
        self.stage = stage
        self.message = message
    }
}

// MARK: - AttemptLoopResult

/// Result of running the candidate attempt loop.
///
/// Contains the full audit trail of all attempts, plus fallback metadata.
/// The caller inspects ``selectedAttempt`` to determine if a viable
/// candidate was found.
public struct AttemptLoopResult: Sendable {
    /// The attempt that was selected for inference, or `nil` if all failed.
    public let selectedAttempt: RouteAttempt?
    /// Full ordered list of attempts tried (including failed ones).
    public let attempts: [RouteAttempt]
    /// Whether a fallback path was used.
    public let fallbackUsed: Bool
    /// What triggered the fallback, if any.
    public let fallbackTrigger: FallbackTrigger?
    /// Index of the first failed attempt that triggered fallback.
    public let fromAttempt: Int?
    /// Index of the attempt that was eventually selected after fallback.
    public let toAttempt: Int?

    /// Whether the loop produced a usable candidate.
    public var succeeded: Bool { selectedAttempt != nil }

    public init(
        selectedAttempt: RouteAttempt? = nil,
        attempts: [RouteAttempt] = [],
        fallbackUsed: Bool = false,
        fallbackTrigger: FallbackTrigger? = nil,
        fromAttempt: Int? = nil,
        toAttempt: Int? = nil
    ) {
        self.selectedAttempt = selectedAttempt
        self.attempts = attempts
        self.fallbackUsed = fallbackUsed
        self.fallbackTrigger = fallbackTrigger
        self.fromAttempt = fromAttempt
        self.toAttempt = toAttempt
    }

    /// Build the attempts/fallback portion for route_metadata.
    public func toRouteMetadataFields() -> [String: Any] {
        let attemptDicts: [[String: Any]] = attempts.compactMap { attempt in
            guard let data = try? JSONEncoder().encode(attempt),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return dict
        }
        var fallbackDict: [String: Any] = [
            "used": fallbackUsed,
            "from_attempt": fromAttempt as Any,
            "to_attempt": toAttempt as Any,
        ]
        if let trigger = fallbackTrigger,
           let data = try? JSONEncoder().encode(trigger),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            fallbackDict["trigger"] = dict
        } else {
            fallbackDict["trigger"] = NSNull()
        }
        return [
            "attempts": attemptDicts,
            "fallback": fallbackDict,
        ]
    }
}

/// Result of an attempt loop that also executed inference for the selected candidate.
public struct AttemptInferenceResult<Value: Sendable>: Sendable {
    public let selectedAttempt: RouteAttempt?
    public let attempts: [RouteAttempt]
    public let fallbackUsed: Bool
    public let fallbackTrigger: FallbackTrigger?
    public let fromAttempt: Int?
    public let toAttempt: Int?
    public let value: Value?
    public let error: Error?

    public init(
        selectedAttempt: RouteAttempt? = nil,
        attempts: [RouteAttempt] = [],
        fallbackUsed: Bool = false,
        fallbackTrigger: FallbackTrigger? = nil,
        fromAttempt: Int? = nil,
        toAttempt: Int? = nil,
        value: Value? = nil,
        error: Error? = nil
    ) {
        self.selectedAttempt = selectedAttempt
        self.attempts = attempts
        self.fallbackUsed = fallbackUsed
        self.fallbackTrigger = fallbackTrigger
        self.fromAttempt = fromAttempt
        self.toAttempt = toAttempt
        self.value = value
        self.error = error
    }
}

// MARK: - Checker Protocols

/// Protocol for checking runtime/engine availability.
///
/// Implementations inspect the device to determine if a given engine
/// is installed and functional. On iOS, this typically checks whether
/// the relevant XCFramework binary (llama, whisper, CoreML model) is
/// present and loadable.
public protocol AttemptRuntimeChecker: Sendable {
    /// Check whether an engine is available for the given locality.
    ///
    /// - Parameters:
    ///   - engine: Engine identifier (e.g. "llama.cpp", "coreml", "mlx-lm"), or nil for cloud.
    ///   - locality: "local" or "cloud".
    /// - Returns: Tuple of (available, reasonCode if not available).
    func check(engine: String?, locality: String) -> (available: Bool, reasonCode: String?)
}

/// Protocol for checking artifact cache and verification.
///
/// On iOS, the SDK's artifact cache manages downloaded model files.
/// This checker verifies the artifact is present, intact (digest match),
/// and available for the engine to load.
public protocol AttemptArtifactChecker: Sendable {
    /// Check artifact availability and integrity.
    ///
    /// - Parameter artifactPlan: The ``RuntimeArtifactPlan`` from the candidate.
    /// - Returns: Tuple of (ok, cacheStatus string, reasonCode if not ok).
    func check(artifactPlan: RuntimeArtifactPlan) -> (ok: Bool, cacheStatus: String, reasonCode: String?)
}

/// Protocol for evaluating per-request gates.
///
/// Gate evaluation is mobile-critical. On iOS:
/// - `min_free_memory_bytes` checks `os_proc_available_memory()`
/// - `min_free_storage_bytes` checks disk space via `FileManager`
/// - `min_tokens_per_second` and `max_ttft_ms` check benchmark cache
/// - `benchmark_fresh` checks benchmark timestamp against window_seconds
public protocol AttemptGateEvaluator: Sendable {
    /// Evaluate a single gate and return the result.
    ///
    /// - Parameters:
    ///   - gate: The gate definition from the candidate.
    ///   - engine: Engine identifier, if local.
    ///   - locality: "local" or "cloud".
    /// - Returns: The gate evaluation result.
    func evaluate(gate: CandidateGate, engine: String?, locality: String) -> GateResult
}

// MARK: - No-Op Defaults

/// Default runtime checker that always reports available.
struct NoOpRuntimeChecker: AttemptRuntimeChecker {
    func check(engine: String?, locality: String) -> (available: Bool, reasonCode: String?) {
        (true, nil)
    }
}

/// Default artifact checker that always reports a cache hit.
struct NoOpArtifactChecker: AttemptArtifactChecker {
    func check(artifactPlan: RuntimeArtifactPlan) -> (ok: Bool, cacheStatus: String, reasonCode: String?) {
        (true, "hit", nil)
    }
}

/// Default gate evaluator that always passes.
struct NoOpGateEvaluator: AttemptGateEvaluator {
    func evaluate(gate: CandidateGate, engine: String?, locality: String) -> GateResult {
        GateResult(code: gate.code, status: .passed)
    }
}

// MARK: - AttemptCandidateInput

/// Typed input for a single candidate in the attempt loop.
///
/// Reuses ``RuntimeCandidatePlan`` from the existing planner schemas
/// and adds the `gates` field introduced by `candidate_gate.schema.json`.
/// This avoids `[String: Any]` dictionaries throughout the runner.
public struct AttemptCandidateInput: Codable, Sendable, Equatable {
    /// The candidate plan from the server planner.
    public let candidate: RuntimeCandidatePlan
    /// Per-request gates the server attached to this candidate.
    public let gates: [CandidateGate]

    public init(candidate: RuntimeCandidatePlan, gates: [CandidateGate] = []) {
        self.candidate = candidate
        self.gates = gates
    }
}

// MARK: - CandidateAttemptRunner

/// Evaluates candidates in priority order through the per-request attempt loop.
///
/// For each candidate:
/// 1. **Prepare** — check runtime/engine availability
/// 2. **Verify** — check artifact cache and integrity (local only)
/// 3. **Gate** — evaluate per-request gates (memory, throughput, TTFT, etc.)
/// 4. **Inference** — all checks passed, candidate selected
///
/// If a candidate fails at any stage and ``fallbackAllowed`` is true,
/// the runner moves to the next candidate. Gate evaluation is mobile-critical:
/// `min_free_memory_bytes` matters on iOS where memory pressure can cause
/// jetsam kills, and model loading is expensive.
///
/// The runner does NOT perform actual inference — it evaluates readiness.
/// The caller invokes inference after the runner selects a candidate.
///
/// This implementation is `Sendable` for safe use in iOS concurrency contexts.
public final class CandidateAttemptRunner: Sendable {
    private let fallbackAllowed: Bool
    private let streaming: Bool
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "CandidateAttemptRunner")

    /// Creates a new attempt runner.
    ///
    /// - Parameters:
    ///   - fallbackAllowed: Whether to try subsequent candidates when one fails.
    ///     Set to `false` for `private`/`local_only` policies that must not fall
    ///     back to cloud.
    ///   - streaming: Whether the caller intends streaming inference.
    public init(fallbackAllowed: Bool = true, streaming: Bool = false) {
        self.fallbackAllowed = fallbackAllowed
        self.streaming = streaming
    }

    /// Streaming may fall back only before any output is emitted to the caller.
    public func shouldFallbackAfterInferenceError(firstOutputEmitted: Bool = false) -> Bool {
        fallbackAllowed && !(streaming && firstOutputEmitted)
    }

    /// Run the attempt loop over candidates.
    ///
    /// - Parameters:
    ///   - candidates: Ordered list of ``AttemptCandidateInput`` from the plan response.
    ///   - runtimeChecker: Checks if a runtime/engine is available.
    ///   - artifactChecker: Checks artifact cache and verification.
    ///   - gateEvaluator: Evaluates per-request gates.
    /// - Returns: ``AttemptLoopResult`` with the selected attempt or failure info.
    public func run(
        candidates: [AttemptCandidateInput],
        runtimeChecker: (any AttemptRuntimeChecker)? = nil,
        artifactChecker: (any AttemptArtifactChecker)? = nil,
        gateEvaluator: (any AttemptGateEvaluator)? = nil
    ) -> AttemptLoopResult {
        let rtCheck = runtimeChecker ?? NoOpRuntimeChecker()
        let artCheck = artifactChecker ?? NoOpArtifactChecker()
        let gateEval = gateEvaluator ?? NoOpGateEvaluator()

        var attempts: [RouteAttempt] = []
        var selected: RouteAttempt?
        var fallbackTrigger: FallbackTrigger?
        var fromAttempt: Int?
        var toAttempt: Int?

        for (idx, input) in candidates.enumerated() {
            let candidate = input.candidate
            let locality = candidate.locality.rawValue
            let mode = Self.modeForLocality(candidate.locality)
            let engine = RuntimeEngineID.canonical(candidate.engine)

            // ------------------------------------------------------------------
            // Stage: prepare — check runtime/engine availability
            // ------------------------------------------------------------------
            let (runtimeOk, runtimeReason) = rtCheck.check(engine: engine, locality: locality)
            var gateResults: [GateResult] = []

            if !runtimeOk {
                gateResults.append(GateResult(
                    code: GateCode.runtimeAvailable.rawValue,
                    status: .failed,
                    reasonCode: runtimeReason
                ))

                let reasonMessage = "\(engine ?? "runtime") not available: \(runtimeReason ?? "unknown")"
                let attempt = RouteAttempt(
                    index: idx,
                    locality: locality,
                    mode: mode,
                    engine: engine,
                    status: .failed,
                    stage: .prepare,
                    gateResults: gateResults,
                    reason: AttemptReason(code: "runtime_unavailable", message: reasonMessage)
                )
                attempts.append(attempt)
                logger.debug("Attempt \(idx): runtime unavailable for \(engine ?? "nil")")

                if fallbackAllowed && idx < candidates.count - 1 {
                    if fallbackTrigger == nil {
                        fallbackTrigger = FallbackTrigger(
                            code: "runtime_unavailable",
                            stage: AttemptStage.prepare.rawValue,
                            message: reasonMessage
                        )
                        fromAttempt = idx
                    }
                    continue
                }
                break
            }

            gateResults.append(GateResult(
                code: GateCode.runtimeAvailable.rawValue,
                status: .passed
            ))

            // ------------------------------------------------------------------
            // Stage: verify artifact (local candidates with artifacts only)
            // ------------------------------------------------------------------
            var artifactInfo: AttemptArtifact?
            if let artifactPlan = candidate.artifact, candidate.locality == .local {
                let (artOk, artStatus, artReason) = artCheck.check(artifactPlan: artifactPlan)
                artifactInfo = AttemptArtifact(
                    id: artifactPlan.artifactId,
                    digest: artifactPlan.digest,
                    cache: AttemptArtifact.CacheInfo(status: artStatus, managedBy: "octomil")
                )

                if artOk {
                    gateResults.append(GateResult(
                        code: GateCode.artifactVerified.rawValue,
                        status: .passed
                    ))
                } else {
                    gateResults.append(GateResult(
                        code: GateCode.artifactVerified.rawValue,
                        status: .failed,
                        reasonCode: artReason
                    ))

                    let reasonMessage = "artifact verification failed: \(artReason ?? "unknown")"
                    let attempt = RouteAttempt(
                        index: idx,
                        locality: locality,
                        mode: mode,
                        engine: engine,
                        artifact: artifactInfo,
                        status: .failed,
                        stage: .verify,
                        gateResults: gateResults,
                        reason: AttemptReason(code: "artifact_verification_failed", message: reasonMessage)
                    )
                    attempts.append(attempt)
                    logger.debug("Attempt \(idx): artifact verification failed")

                    if fallbackAllowed && idx < candidates.count - 1 {
                        if fallbackTrigger == nil {
                            fallbackTrigger = FallbackTrigger(
                                code: "artifact_verification_failed",
                                stage: AttemptStage.verify.rawValue,
                                message: reasonMessage
                            )
                            fromAttempt = idx
                        }
                        continue
                    }
                    break
                }
            }

            // ------------------------------------------------------------------
            // Stage: gate — evaluate per-request gates
            // ------------------------------------------------------------------
            let gates = input.gates
            var gateFailed = false
            for gate in gates {
                // Skip gates already evaluated in earlier stages.
                if gate.code == GateCode.runtimeAvailable.rawValue
                    || gate.code == GateCode.artifactVerified.rawValue {
                    continue
                }

                let result = gateEval.evaluate(gate: gate, engine: engine, locality: locality)
                gateResults.append(result)

                if result.status == .failed && gate.required {
                    gateFailed = true

                    let reasonMessage = "\(gate.code) gate failed"
                    let attempt = RouteAttempt(
                        index: idx,
                        locality: locality,
                        mode: mode,
                        engine: engine,
                        artifact: artifactInfo,
                        status: .failed,
                        stage: .gate,
                        gateResults: gateResults,
                        reason: AttemptReason(code: "gate_failed", message: reasonMessage)
                    )
                    attempts.append(attempt)
                    logger.debug("Attempt \(idx): gate \(gate.code) failed")

                    if fallbackAllowed && idx < candidates.count - 1 {
                        if fallbackTrigger == nil {
                            fallbackTrigger = FallbackTrigger(
                                code: "gate_failed",
                                stage: AttemptStage.gate.rawValue,
                                message: reasonMessage
                            )
                            fromAttempt = idx
                        }
                        // Continue to next candidate
                    }
                    break // Break inner gate loop; outer loop continues via gateFailed
                }
            }

            if gateFailed {
                if !fallbackAllowed || idx >= candidates.count - 1 {
                    break
                }
                continue
            }

            // ------------------------------------------------------------------
            // Stage: inference — candidate selected
            // ------------------------------------------------------------------
            let attempt = RouteAttempt(
                index: idx,
                locality: locality,
                mode: mode,
                engine: engine,
                artifact: artifactInfo,
                status: .selected,
                stage: .inference,
                gateResults: gateResults,
                reason: AttemptReason(code: "selected", message: "all gates passed, candidate selected")
            )
            attempts.append(attempt)
            selected = attempt
            if fallbackTrigger != nil {
                toAttempt = idx
            }
            logger.debug("Attempt \(idx): selected \(locality)/\(engine ?? "nil")")
            break
        }

        let hasFallback = fallbackTrigger != nil && selected != nil
        return AttemptLoopResult(
            selectedAttempt: selected,
            attempts: attempts,
            fallbackUsed: hasFallback,
            fallbackTrigger: hasFallback ? fallbackTrigger : nil,
            fromAttempt: hasFallback ? fromAttempt : nil,
            toAttempt: toAttempt
        )
    }

    /// Run readiness checks and execute inference for the selected candidate.
    ///
    /// This product-path method records inference-stage failures instead of
    /// declaring a candidate selected before the request actually runs.
    public func runWithInference<Value: Sendable>(
        candidates: [AttemptCandidateInput],
        runtimeChecker: (any AttemptRuntimeChecker)? = nil,
        artifactChecker: (any AttemptArtifactChecker)? = nil,
        gateEvaluator: (any AttemptGateEvaluator)? = nil,
        firstOutputEmitted: @Sendable () -> Bool = { false },
        executeCandidate: @Sendable (AttemptCandidateInput, RouteAttempt) async throws -> Value
    ) async -> AttemptInferenceResult<Value> {
        var attempts: [RouteAttempt] = []
        var fallbackTrigger: FallbackTrigger?
        var fromAttempt: Int?
        var toAttempt: Int?
        var lastError: Error?

        for (idx, input) in candidates.enumerated() {
            let readiness = CandidateAttemptRunner(fallbackAllowed: false, streaming: streaming).run(
                candidates: [input],
                runtimeChecker: runtimeChecker,
                artifactChecker: artifactChecker,
                gateEvaluator: gateEvaluator
            )

            guard let selectedAttempt = readiness.selectedAttempt else {
                if var failedAttempt = readiness.attempts.first {
                    failedAttempt = RouteAttempt(
                        index: idx,
                        locality: failedAttempt.locality,
                        mode: failedAttempt.mode,
                        engine: failedAttempt.engine,
                        artifact: failedAttempt.artifact,
                        status: failedAttempt.status,
                        stage: failedAttempt.stage,
                        gateResults: failedAttempt.gateResults,
                        reason: failedAttempt.reason
                    )
                    attempts.append(failedAttempt)
                    if fallbackTrigger == nil {
                        fallbackTrigger = FallbackTrigger(
                            code: failedAttempt.reason.code,
                            stage: failedAttempt.stage.rawValue,
                            message: failedAttempt.reason.message
                        )
                        fromAttempt = idx
                    }
                }
                if !fallbackAllowed { break }
                continue
            }

            let indexedSelection = RouteAttempt(
                index: idx,
                locality: selectedAttempt.locality,
                mode: selectedAttempt.mode,
                engine: selectedAttempt.engine,
                artifact: selectedAttempt.artifact,
                status: selectedAttempt.status,
                stage: selectedAttempt.stage,
                gateResults: selectedAttempt.gateResults,
                reason: selectedAttempt.reason
            )

            do {
                let value = try await executeCandidate(input, indexedSelection)
                attempts.append(indexedSelection)
                if fallbackTrigger != nil { toAttempt = idx }
                let hasFallback = fallbackTrigger != nil
                return AttemptInferenceResult(
                    selectedAttempt: indexedSelection,
                    attempts: attempts,
                    fallbackUsed: hasFallback,
                    fallbackTrigger: hasFallback ? fallbackTrigger : nil,
                    fromAttempt: hasFallback ? fromAttempt : nil,
                    toAttempt: hasFallback ? toAttempt : nil,
                    value: value
                )
            } catch {
                lastError = error
                let emitted = firstOutputEmitted()
                let code: String
                if streaming && emitted {
                    code = "inference_error_after_first_output"
                } else if streaming {
                    code = "inference_error_before_first_output"
                } else {
                    code = "inference_error"
                }
                let failedAttempt = RouteAttempt(
                    index: idx,
                    locality: indexedSelection.locality,
                    mode: indexedSelection.mode,
                    engine: indexedSelection.engine,
                    artifact: indexedSelection.artifact,
                    status: .failed,
                    stage: .inference,
                    gateResults: indexedSelection.gateResults,
                    reason: AttemptReason(code: code, message: error.localizedDescription)
                )
                attempts.append(failedAttempt)
                if fallbackTrigger == nil {
                    fallbackTrigger = FallbackTrigger(code: code, stage: AttemptStage.inference.rawValue, message: failedAttempt.reason.message)
                    fromAttempt = idx
                }
                if idx >= candidates.count - 1 || !shouldFallbackAfterInferenceError(firstOutputEmitted: emitted) {
                    break
                }
            }
        }

        return AttemptInferenceResult(
            selectedAttempt: nil,
            attempts: attempts,
            fallbackUsed: false,
            fallbackTrigger: nil,
            fromAttempt: nil,
            toAttempt: nil,
            error: lastError
        )
    }

    // MARK: - Helpers

    /// Derive execution mode from candidate locality.
    static func modeForLocality(_ locality: RuntimeLocality) -> String {
        switch locality {
        case .local: return "sdk_runtime"
        case .cloud: return "hosted_gateway"
        }
    }
}

import Foundation
import CoreML
import os.log

/// Decides the optimal compute strategy based on the current device state.
///
/// Call ``recommend(for:)`` for local-only heuristics, or
/// ``recommend(for:using:deviceId:modelId:currentFormat:)`` to try the
/// server adaptation endpoint first and fall back to local heuristics.
public struct RuntimeAdapter: Sendable {

    // MARK: - Types

    /// A recommendation for how to configure inference given current device conditions.
    public struct ComputeRecommendation: Sendable, Equatable {
        /// Which CoreML compute units to use.
        public let computeUnits: MLComputeUnits
        /// Whether inference should be throttled (delayed between calls).
        public let shouldThrottle: Bool
        /// Whether batch sizes should be reduced.
        public let reduceBatchSize: Bool
        /// Maximum number of concurrent inference requests.
        public let maxConcurrentInferences: Int
        /// Human-readable reason for this recommendation.
        public let reason: String

        public init(
            computeUnits: MLComputeUnits,
            shouldThrottle: Bool,
            reduceBatchSize: Bool,
            maxConcurrentInferences: Int,
            reason: String
        ) {
            self.computeUnits = computeUnits
            self.shouldThrottle = shouldThrottle
            self.reduceBatchSize = reduceBatchSize
            self.maxConcurrentInferences = maxConcurrentInferences
            self.reason = reason
        }
    }

    // MARK: - Logging

    private static let logger = Logger(subsystem: "ai.octomil.sdk", category: "RuntimeAdapter")

    // MARK: - Server-Backed Adaptation

    /// Returns a compute recommendation, trying the server adapt endpoint first.
    ///
    /// If `apiClient` is non-nil and the server is reachable, the recommendation
    /// comes from `POST /api/v1/devices/{deviceId}/models/{modelId}/adapt`.
    /// If the server is unreachable or `apiClient` is nil, falls back to the
    /// local heuristics in ``recommend(for:)``.
    ///
    /// - Parameters:
    ///   - state: Current device state snapshot.
    ///   - apiClient: Optional API client for server communication.
    ///   - deviceId: Server-assigned device UUID. Required when apiClient is non-nil.
    ///   - modelId: Model identifier. Required when apiClient is non-nil.
    ///   - currentFormat: Current model format (e.g. "coreml"). Defaults to "coreml".
    /// - Returns: A compute recommendation from the server or local fallback.
    public static func recommend(
        for state: DeviceStateMonitor.DeviceState,
        using apiClient: APIClient?,
        deviceId: String?,
        modelId: String?,
        currentFormat: String = "coreml"
    ) async -> ComputeRecommendation {
        // If we have all the pieces for a server call, try it first.
        if let apiClient, let deviceId, let modelId {
            let localFallback = recommend(for: state)
            let currentExecutor = computeUnitsToString(localFallback.computeUnits)
            let thermalString = state.thermalState.rawValue

            do {
                let serverRec = try await apiClient.getAdaptationRecommendation(
                    deviceId: deviceId,
                    modelId: modelId,
                    batteryLevel: state.batteryLevel,
                    thermalState: thermalString,
                    currentFormat: currentFormat,
                    currentExecutor: currentExecutor
                )

                let units = parseComputeUnits(serverRec.recommendedComputeUnits)
                // Server doesn't provide maxConcurrentInferences -- derive from compute units.
                let maxConcurrent = deriveMaxConcurrency(for: units, throttle: serverRec.throttleInference)

                logger.debug("Using server adaptation recommendation: \(serverRec.recommendedComputeUnits)")
                return ComputeRecommendation(
                    computeUnits: units,
                    shouldThrottle: serverRec.throttleInference,
                    reduceBatchSize: serverRec.reduceBatchSize,
                    maxConcurrentInferences: maxConcurrent,
                    reason: "Server recommendation: \(serverRec.recommendedComputeUnits)"
                )
            } catch {
                logger.info("Server adapt endpoint unreachable, falling back to local heuristics: \(error.localizedDescription)")
            }
        }

        // Fallback: local heuristics
        return recommend(for: state)
    }

    // MARK: - Local Heuristics (Fallback)

    /// Returns a compute recommendation based on current device conditions using
    /// local heuristics only. No network calls are made.
    public static func recommend(for state: DeviceStateMonitor.DeviceState) -> ComputeRecommendation {
        // 1. Critical thermal — shed as much heat as possible
        if state.thermalState == .critical {
            return ComputeRecommendation(
                computeUnits: .cpuOnly,
                shouldThrottle: true,
                reduceBatchSize: true,
                maxConcurrentInferences: 1,
                reason: "Device critically hot — CPU only with throttling"
            )
        }

        // 2. Serious thermal — avoid ANE (highest heat generation)
        if state.thermalState == .serious {
            return ComputeRecommendation(
                computeUnits: .cpuAndGPU,
                shouldThrottle: false,
                reduceBatchSize: false,
                maxConcurrentInferences: 2,
                reason: "Device running hot — bypassing Neural Engine"
            )
        }

        // 3. Battery critically low (< 10%)
        if state.batteryLevel >= 0 && state.batteryLevel < 0.10 {
            return ComputeRecommendation(
                computeUnits: .cpuOnly,
                shouldThrottle: false,
                reduceBatchSize: true,
                maxConcurrentInferences: 1,
                reason: "Battery critically low — CPU only, reduced batch"
            )
        }

        // 4. Battery low (< 20%) and not charging
        if state.batteryLevel >= 0 && state.batteryLevel < 0.20 && state.batteryState == .unplugged {
            return ComputeRecommendation(
                computeUnits: .cpuAndGPU,
                shouldThrottle: false,
                reduceBatchSize: false,
                maxConcurrentInferences: 2,
                reason: "Conserving battery — bypassing Neural Engine"
            )
        }

        // 5. Low Power Mode enabled
        if state.isLowPowerMode {
            return ComputeRecommendation(
                computeUnits: .cpuAndGPU,
                shouldThrottle: false,
                reduceBatchSize: false,
                maxConcurrentInferences: 1,
                reason: "Low Power Mode — reduced concurrency"
            )
        }

        // 6. All clear — full performance
        return ComputeRecommendation(
            computeUnits: .all,
            shouldThrottle: false,
            reduceBatchSize: false,
            maxConcurrentInferences: 4,
            reason: "Nominal — full compute available"
        )
    }

    // MARK: - Helpers

    /// Parses a compute units string from the server into `MLComputeUnits`.
    static func parseComputeUnits(_ string: String) -> MLComputeUnits {
        switch string.lowercased() {
        case "cpuonly", "cpu_only":
            return .cpuOnly
        case "cpuandgpu", "cpu_and_gpu":
            return .cpuAndGPU
        case "all":
            return .all
        case "cpuandneuralengine", "cpu_and_neural_engine":
            if #available(iOS 16.0, macOS 13.0, *) {
                return .cpuAndNeuralEngine
            }
            return .all
        default:
            return .all
        }
    }

    /// Converts `MLComputeUnits` to a string for the server request.
    static func computeUnitsToString(_ units: MLComputeUnits) -> String {
        switch units {
        case .all: return "all"
        case .cpuAndGPU: return "cpuAndGPU"
        case .cpuOnly: return "cpuOnly"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        @unknown default: return "all"
        }
    }

    /// Derives max concurrency from compute units and throttle state.
    /// The server doesn't provide this field, so we infer it.
    private static func deriveMaxConcurrency(for units: MLComputeUnits, throttle: Bool) -> Int {
        if throttle {
            return 1
        }
        switch units {
        case .all:
            return 4
        case .cpuAndGPU, .cpuAndNeuralEngine:
            return 2
        case .cpuOnly:
            return 1
        @unknown default:
            return 2
        }
    }
}

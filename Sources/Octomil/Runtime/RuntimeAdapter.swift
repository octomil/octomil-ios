import Foundation
import CoreML

/// Decides the optimal compute strategy based on the current device state.
///
/// Call ``recommend(for:)`` with a ``DeviceStateMonitor/DeviceState`` to get a
/// ``ComputeRecommendation`` that specifies which CoreML compute units to use,
/// whether to throttle inference, and concurrency limits.
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

    // MARK: - Public API

    /// Returns a compute recommendation based on current device conditions.
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
}

import CryptoKit
import Foundation

// MARK: - Models

/// An A/B experiment with variants.
public struct Experiment: Codable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let variants: [ExperimentVariant]
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, status, variants
        case createdAt = "created_at"
    }
}

/// A single experiment variant.
public struct ExperimentVariant: Codable, Sendable {
    public let id: String
    public let name: String
    public let modelId: String
    public let modelVersion: String
    public let trafficPercentage: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case modelId = "model_id"
        case modelVersion = "model_version"
        case trafficPercentage = "traffic_percentage"
    }
}

/// Result of resolving which experiment affects a model.
public struct ModelExperimentResult: Sendable {
    public let experiment: Experiment
    public let variant: ExperimentVariant
}

// MARK: - Client

/// Client for managing A/B experiments.
///
/// Provides cross-SDK parity with Python's `ExperimentsAPI`, Android's
/// `ExperimentsClient`, and Node's `ExperimentsClient`.
public final class ExperimentsClient: @unchecked Sendable {
    private let apiClient: APIClient
    private let telemetryQueue: TelemetryQueue?

    public init(apiClient: APIClient, telemetryQueue: TelemetryQueue? = nil) {
        self.apiClient = apiClient
        self.telemetryQueue = telemetryQueue
    }

    /// Fetch all active experiments.
    public func getActiveExperiments() async throws -> [Experiment] {
        try await apiClient.getActiveExperiments()
    }

    /// Fetch config for a specific experiment.
    public func getExperimentConfig(experimentId: String) async throws -> Experiment {
        try await apiClient.getExperimentConfig(experimentId: experimentId)
    }

    /// Get the variant assigned to a device using deterministic hashing.
    ///
    /// Only returns a variant for active experiments.
    public func getVariant(experiment: Experiment, deviceId: String) -> ExperimentVariant? {
        guard experiment.status == "active" else { return nil }
        guard !experiment.variants.isEmpty else { return nil }

        let key = "\(experiment.id):\(deviceId)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let bucket = Int(digest.prefix(4).reduce(0 as UInt32) { $0 << 8 | UInt32($1) } % 100)

        var cumulative = 0
        for variant in experiment.variants {
            cumulative += variant.trafficPercentage
            if bucket < cumulative {
                telemetryQueue?.reportExperimentAssigned(
                    modelId: variant.modelId,
                    experimentId: experiment.id,
                    variant: variant.name
                )
                return variant
            }
        }
        return nil
    }

    /// Check if a device is enrolled in an experiment.
    public func isEnrolled(experiment: Experiment, deviceId: String) -> Bool {
        getVariant(experiment: experiment, deviceId: deviceId) != nil
    }

    /// Find the experiment (if any) that affects a given model.
    public func resolveModelExperiment(modelId: String, deviceId: String) async -> ModelExperimentResult? {
        guard let experiments = try? await getActiveExperiments() else { return nil }

        for experiment in experiments {
            let hasModel = experiment.variants.contains { $0.modelId == modelId }
            guard hasModel else { continue }

            if let variant = getVariant(experiment: experiment, deviceId: deviceId) {
                return ModelExperimentResult(experiment: experiment, variant: variant)
            }
        }
        return nil
    }

    /// Track a metric for an experiment.
    public func trackMetric(
        experimentId: String,
        metricName: String,
        metricValue: Double,
        deviceId: String? = nil
    ) async throws {
        let event = TrackingEvent(
            name: metricName,
            properties: [
                "metric_name": metricName,
                "metric_value": String(metricValue),
                "device_id": deviceId ?? ""
            ]
        )
        try await apiClient.trackMetric(experimentId: experimentId, event: event)

        telemetryQueue?.reportExperimentMetric(
            experimentId: experimentId,
            metricName: metricName,
            metricValue: metricValue
        )
    }
}

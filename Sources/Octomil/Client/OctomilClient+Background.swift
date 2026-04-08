import Foundation
import CoreML

// MARK: - Background Operations, Analytics & Metrics

extension OctomilClient {

    // MARK: - Background Operations

    /// Enables background training when conditions are met.
    ///
    /// Background training runs during device idle time when:
    /// - Device is connected to power (optional)
    /// - Network is available
    /// - Battery level is sufficient
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - constraints: Background execution constraints.
    #if os(iOS)
    public func enableBackgroundTraining(
        modelId: String,
        dataProvider: @escaping @Sendable () -> MLBatchProvider,
        constraints: BackgroundConstraints = .standard
    ) {
        let sync = BackgroundSync.shared
        sync.configure(
            modelId: modelId,
            dataProvider: dataProvider,
            constraints: constraints,
            client: self
        )
        sync.scheduleNextTraining()

        if configuration.enableLogging {
            logger.info("Background training enabled for model: \(modelId)")
        }
    }

    /// Disables background training.
    public func disableBackgroundTraining() {
        BackgroundSync.shared.cancelScheduledTraining()

        if configuration.enableLogging {
            logger.info("Background training disabled")
        }
    }
    #endif

    // MARK: - Federated Analytics

    /// Creates a federated analytics client for the given federation.
    ///
    /// - Parameter federationId: The federation to run analytics against.
    /// - Returns: A ``FederatedAnalyticsClient`` bound to this client's API connection.
    public func analytics(federationId: String) -> FederatedAnalyticsClient {
        return FederatedAnalyticsClient(apiClient: apiClient, federationId: federationId)
    }

    // MARK: - Metric Tracking

    /// Tracks a metric for an experiment.
    ///
    /// Metrics are persisted to the local event queue first (offline-first),
    /// then forwarded to the server.
    ///
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - eventName: Name of the event.
    ///   - properties: Event properties.
    public func trackMetric(
        experimentId: String,
        eventName: String,
        properties: [String: String] = [:]
    ) async throws {
        let event = TrackingEvent(
            name: eventName,
            properties: properties,
            timestamp: Date()
        )

        // Persist to local queue first (offline-first)
        await eventQueue.addTrainingEvent(
            type: eventName,
            metadata: properties
        )

        // Report experiment metric if properties contain metric_name and metric_value
        if let metricName = properties["metric_name"],
           let metricValueStr = properties["metric_value"],
           let metricValue = Double(metricValueStr) {
            TelemetryQueue.shared?.reportExperimentMetric(
                experimentId: experimentId,
                metricName: metricName,
                metricValue: metricValue
            )
        }

        try await apiClient.trackMetric(experimentId: experimentId, event: event)
    }

    // MARK: - Round Management

    /// Checks if this device has been selected for an active training round.
    ///
    /// Polls the server for rounds in the "waiting_for_updates" state for the
    /// given model. Returns the first matching round assignment, or nil
    /// if no round is currently active for this device.
    ///
    /// - Parameter modelId: The model to check for round assignments.
    /// - Returns: The round assignment, or nil if none available.
    /// - Throws: `OctomilError` if the request fails.
    public func checkForRoundAssignment(modelId: String) async throws -> RoundAssignment? {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        let rounds = try await apiClient.listRounds(
            modelId: modelId,
            state: "waiting_for_updates",
            deviceId: deviceId
        )

        return rounds.first
    }

    /// Gets the current status of a training round.
    ///
    /// - Parameter roundId: The round to query.
    /// - Returns: The round details.
    /// - Throws: `OctomilError` if the request fails.
    public func getRoundStatus(roundId: String) async throws -> RoundAssignment {
        return try await apiClient.getRound(roundId: roundId)
    }
}

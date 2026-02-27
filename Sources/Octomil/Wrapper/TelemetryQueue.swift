import Foundation
import os.log

/// A single inference telemetry event (v1 legacy format, kept for persistence compatibility).
public struct InferenceTelemetryEvent: Codable, Sendable {
    /// Model identifier.
    public let modelId: String
    /// Inference latency in milliseconds.
    public let latencyMs: Double
    /// Millisecond-precision Unix timestamp.
    public let timestamp: Int64
    /// Whether the prediction succeeded.
    public let success: Bool
    /// Optional error message on failure.
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case latencyMs = "latency_ms"
        case timestamp
        case success
        case errorMessage = "error_message"
    }

    public init(
        modelId: String,
        latencyMs: Double,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        self.modelId = modelId
        self.latencyMs = latencyMs
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
    }

    /// Converts this legacy event to a v2 `TelemetryEvent`.
    func toV2Event() -> TelemetryEvent {
        let name = success ? "inference.completed" : "inference.failed"
        let iso = ISO8601DateFormatter()
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)

        var attrs: [String: TelemetryValue] = [
            "model.id": .string(modelId),
            "inference.duration_ms": .double(latencyMs),
            "model.format": .string("coreml"),
        ]
        if !success {
            attrs["inference.success"] = .bool(false)
        }
        if let errorMessage {
            attrs["error.message"] = .string(errorMessage)
        }

        return TelemetryEvent(
            name: name,
            timestamp: iso.string(from: date),
            attributes: attrs
        )
    }
}

/// Batches telemetry events and sends them to the Octomil server using the
/// v2 OTLP envelope format (`POST /api/v2/telemetry/events`).
///
/// Events are accumulated in memory and flushed either when the batch size
/// is reached or when a periodic timer fires. Unsent events are persisted
/// to disk so they survive app termination and can be retried on next launch.
///
/// Both inference events and funnel events are sent through the unified v2 endpoint.
public final class TelemetryQueue: @unchecked Sendable {

    // MARK: - Shared Funnel Reporter

    /// Shared instance used for funnel/telemetry event reporting from classes
    /// that don't hold a direct TelemetryQueue reference.
    /// Set automatically when the first TelemetryQueue is created with a serverURL.
    public private(set) static var shared: TelemetryQueue?

    // MARK: - Properties

    private let modelId: String
    private let serverURL: URL?
    private let apiKey: String?
    private let batchSize: Int
    private let flushInterval: TimeInterval
    private let logger: Logger

    /// Device ID for the v2 resource envelope. Populated lazily.
    private var deviceId: String?
    /// Org ID for the v2 resource envelope.
    private var orgId: String?

    private let lock = NSLock()
    private var buffer: [TelemetryEvent] = []
    private var flushTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "ai.octomil.telemetry.timer")
    private let persistenceURL: URL

    /// Current number of buffered (unsent) events.
    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    // MARK: - Initialization

    /// Creates a telemetry queue.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier for this queue.
    ///   - serverURL: Base URL for the telemetry endpoint.
    ///   - apiKey: API key for authentication.
    ///   - batchSize: Flush when this many events have accumulated.
    ///   - flushInterval: Maximum seconds between automatic flushes.
    ///   - deviceId: Stable device identifier for the v2 resource.
    ///   - orgId: Organization identifier for the v2 resource.
    public init(
        modelId: String,
        serverURL: URL? = nil,
        apiKey: String? = nil,
        batchSize: Int = 50,
        flushInterval: TimeInterval = 30,
        deviceId: String? = nil,
        orgId: String? = nil
    ) {
        self.modelId = modelId
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.batchSize = max(batchSize, 1)
        self.flushInterval = flushInterval
        self.deviceId = deviceId
        self.orgId = orgId
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "TelemetryQueue")

        // Persistence location
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.persistenceURL = appSupport
            .appendingPathComponent("octomil_telemetry", isDirectory: true)
            .appendingPathComponent("\(modelId)_v2_events.json")

        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        restorePersistedEvents()
        startFlushTimer()

        if serverURL != nil && TelemetryQueue.shared == nil {
            TelemetryQueue.shared = self
        }
    }

    /// Creates a telemetry queue using an explicit persistence URL (for testing).
    internal init(
        modelId: String,
        serverURL: URL?,
        apiKey: String?,
        batchSize: Int,
        flushInterval: TimeInterval,
        persistenceURL: URL,
        deviceId: String? = nil,
        orgId: String? = nil
    ) {
        self.modelId = modelId
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.batchSize = max(batchSize, 1)
        self.flushInterval = flushInterval
        self.deviceId = deviceId
        self.orgId = orgId
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "TelemetryQueue")
        self.persistenceURL = persistenceURL

        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        restorePersistedEvents()
        startFlushTimer()
    }

    deinit {
        flushTimer?.cancel()
        persistEvents()
    }

    // MARK: - Resource Configuration

    /// Sets the device and org IDs for the v2 OTLP resource envelope.
    public func setResourceContext(deviceId: String, orgId: String) {
        lock.lock()
        self.deviceId = deviceId
        self.orgId = orgId
        lock.unlock()
    }

    // MARK: - Public API (v2 TelemetryEvent)

    /// Records a v2 telemetry event.
    ///
    /// When the buffer reaches ``batchSize`` the queue is flushed automatically.
    public func recordEvent(_ event: TelemetryEvent) {
        lock.lock()
        buffer.append(event)
        let shouldFlush = buffer.count >= batchSize
        lock.unlock()

        if shouldFlush {
            flushAsync()
        }
    }

    /// Records a legacy v1 inference event by converting it to v2 format.
    public func record(_ event: InferenceTelemetryEvent) {
        recordEvent(event.toV2Event())
    }

    /// Convenience to report a completed inference.
    public func reportInferenceCompleted(latencyMs: Double) {
        let event = TelemetryEvent(
            name: "inference.completed",
            attributes: [
                "model.id": .string(modelId),
                "inference.duration_ms": .double(latencyMs),
                "model.format": .string("coreml"),
            ]
        )
        recordEvent(event)
    }

    /// Convenience to report a failed inference.
    public func reportInferenceFailed(latencyMs: Double, error: String) {
        let event = TelemetryEvent(
            name: "inference.failed",
            attributes: [
                "model.id": .string(modelId),
                "inference.duration_ms": .double(latencyMs),
                "inference.success": .bool(false),
                "error.message": .string(error),
                "model.format": .string("coreml"),
            ]
        )
        recordEvent(event)
    }

    // MARK: - Inference Started

    /// Reports an `inference.started` event before inference runs.
    ///
    /// - Parameter modelId: The model identifier for the inference.
    public func reportInferenceStarted(modelId: String) {
        let event = TelemetryEvent(
            name: "inference.started",
            attributes: [
                "model.id": .string(modelId),
                "model.format": .string("coreml"),
            ]
        )
        recordEvent(event)
    }

    // MARK: - Training Events

    /// Records a `training.started` event.
    public func reportTrainingStarted(
        modelId: String,
        version: String,
        roundId: String,
        numSamples: Int
    ) {
        let event = TelemetryEvent(
            name: "training.started",
            attributes: [
                "model.id": .string(modelId),
                "model.version": .string(version),
                "training.round_id": .string(roundId),
                "training.num_samples": .int(numSamples),
            ]
        )
        recordEvent(event)
    }

    /// Records a `training.completed` event.
    public func reportTrainingCompleted(
        modelId: String,
        version: String,
        durationMs: Double,
        loss: Double,
        accuracy: Double
    ) {
        let event = TelemetryEvent(
            name: "training.completed",
            attributes: [
                "model.id": .string(modelId),
                "model.version": .string(version),
                "training.duration_ms": .double(durationMs),
                "training.loss": .double(loss),
                "training.accuracy": .double(accuracy),
            ]
        )
        recordEvent(event)
    }

    /// Records a `training.failed` event.
    public func reportTrainingFailed(
        modelId: String,
        version: String,
        errorType: String,
        errorMessage: String
    ) {
        let event = TelemetryEvent(
            name: "training.failed",
            attributes: [
                "model.id": .string(modelId),
                "model.version": .string(version),
                "error.type": .string(errorType),
                "error.message": .string(errorMessage),
            ]
        )
        recordEvent(event)
    }

    /// Records a `training.weight_upload` event.
    public func reportWeightUpload(
        modelId: String,
        roundId: String,
        sampleCount: Int
    ) {
        let event = TelemetryEvent(
            name: "training.weight_upload",
            attributes: [
                "model.id": .string(modelId),
                "training.round_id": .string(roundId),
                "training.sample_count": .int(sampleCount),
            ]
        )
        recordEvent(event)
    }

    // MARK: - Experiment Events

    /// Records an `experiment.assigned` event.
    public func reportExperimentAssigned(
        modelId: String,
        experimentId: String,
        variant: String
    ) {
        let event = TelemetryEvent(
            name: "experiment.assigned",
            attributes: [
                "model.id": .string(modelId),
                "experiment.id": .string(experimentId),
                "experiment.variant": .string(variant),
            ]
        )
        recordEvent(event)
    }

    /// Records an `experiment.metric_recorded` event.
    public func reportExperimentMetric(
        experimentId: String,
        metricName: String,
        metricValue: Double
    ) {
        let event = TelemetryEvent(
            name: "experiment.metric_recorded",
            attributes: [
                "experiment.id": .string(experimentId),
                "experiment.metric_name": .string(metricName),
                "experiment.metric_value": .double(metricValue),
            ]
        )
        recordEvent(event)
    }

    // MARK: - Deploy Events

    /// Records a `deploy.started` event.
    public func reportDeployStarted(modelId: String, version: String) {
        let event = TelemetryEvent(
            name: "deploy.started",
            attributes: [
                "model.id": .string(modelId),
                "model.version": .string(version),
            ]
        )
        recordEvent(event)
    }

    /// Records a `deploy.completed` event.
    public func reportDeployCompleted(
        modelId: String,
        version: String,
        durationMs: Double
    ) {
        let event = TelemetryEvent(
            name: "deploy.completed",
            attributes: [
                "model.id": .string(modelId),
                "model.version": .string(version),
                "deploy.duration_ms": .double(durationMs),
            ]
        )
        recordEvent(event)
    }

    /// Records a `deploy.rollback` event.
    public func reportDeployRollback(
        modelId: String,
        fromVersion: String,
        toVersion: String,
        reason: String
    ) {
        let event = TelemetryEvent(
            name: "deploy.rollback",
            attributes: [
                "model.id": .string(modelId),
                "deploy.from_version": .string(fromVersion),
                "deploy.to_version": .string(toVersion),
                "deploy.reason": .string(reason),
            ]
        )
        recordEvent(event)
    }

    /// Forces an immediate async flush of all buffered events.
    public func flushAsync() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.flush()
        }
    }

    /// Persists unsent events to disk.
    ///
    /// Call this when the app moves to the background to avoid losing events.
    public func persistEvents() {
        lock.lock()
        let snapshot = buffer
        lock.unlock()

        guard !snapshot.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist telemetry events: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal / Private

    /// Sends all buffered events to the server using v2 OTLP envelope.
    internal func flush() async {
        let batch = drainBuffer()

        guard !batch.isEmpty else { return }

        guard let serverURL else {
            logger.debug("No server URL configured; discarding \(batch.count) telemetry events")
            return
        }

        let resource = buildResource()
        let envelope = TelemetryEnvelope(resource: resource, events: batch)

        let url = serverURL.appendingPathComponent("api/v2/telemetry/events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("octomil-ios/\(OctomilVersion.current)", forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(envelope)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                logger.warning("Telemetry upload returned HTTP \(httpResponse.statusCode)")
                requeueEvents(batch)
            } else {
                try? FileManager.default.removeItem(at: persistenceURL)
            }
        } catch {
            logger.warning("Telemetry upload failed: \(error.localizedDescription)")
            requeueEvents(batch)
        }
    }

    private func buildResource() -> TelemetryResource {
        lock.lock()
        let devId = deviceId ?? "unknown"
        let org = orgId ?? "unknown"
        lock.unlock()

        return TelemetryResource(
            deviceId: devId,
            orgId: org
        )
    }

    /// Returns a snapshot of the current buffer for testing.
    internal var bufferedEvents: [TelemetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// Atomically drains the buffer and returns the events.
    private func drainBuffer() -> [TelemetryEvent] {
        lock.lock()
        let batch = buffer
        buffer.removeAll()
        lock.unlock()
        return batch
    }

    /// Re-inserts events at the front of the buffer after a failed upload.
    private func requeueEvents(_ events: [TelemetryEvent]) {
        lock.lock()
        buffer.insert(contentsOf: events, at: 0)
        lock.unlock()
    }

    private func startFlushTimer() {
        guard flushInterval > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(
            deadline: .now() + flushInterval,
            repeating: flushInterval
        )
        timer.setEventHandler { [weak self] in
            self?.flushAsync()
        }
        timer.resume()
        flushTimer = timer
    }

    private func restorePersistedEvents() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let events = try JSONDecoder().decode([TelemetryEvent].self, from: data)
            lock.lock()
            buffer.insert(contentsOf: events, at: 0)
            lock.unlock()
            try? FileManager.default.removeItem(at: persistenceURL)
            logger.debug("Restored \(events.count) persisted telemetry events")
        } catch {
            logger.warning("Failed to restore persisted events: \(error.localizedDescription)")
        }
    }

    // MARK: - Funnel Events (now via v2 unified endpoint)

    /// Report a funnel analytics event via the v2 telemetry endpoint.
    ///
    /// Funnel events are converted to v2 `TelemetryEvent` with `funnel.*` names
    /// and sent through the same batched queue as inference events.
    public func reportFunnelEvent(
        stage: String,
        success: Bool = true,
        deviceId: String? = nil,
        modelId: String? = nil,
        rolloutId: String? = nil,
        sessionId: String? = nil,
        failureReason: String? = nil,
        failureCategory: String? = nil,
        durationMs: Int? = nil,
        platform: String? = nil,
        metadata: [String: String]? = nil
    ) {
        var attrs: [String: TelemetryValue] = [
            "funnel.success": .bool(success),
            "funnel.source": .string("sdk_ios"),
        ]

        if let deviceId { attrs["device.id"] = .string(deviceId) }
        if let modelId { attrs["model.id"] = .string(modelId) }
        if let rolloutId { attrs["funnel.rollout_id"] = .string(rolloutId) }
        if let sessionId { attrs["funnel.session_id"] = .string(sessionId) }
        if let failureReason { attrs["error.message"] = .string(failureReason) }
        if let failureCategory { attrs["error.category"] = .string(failureCategory) }
        if let durationMs { attrs["funnel.duration_ms"] = .int(durationMs) }
        attrs["funnel.platform"] = .string(platform ?? "ios")
        attrs["funnel.sdk_version"] = .string(OctomilVersion.current)

        if let metadata {
            for (key, value) in metadata {
                attrs["funnel.metadata.\(key)"] = .string(value)
            }
        }

        let event = TelemetryEvent(
            name: "funnel.\(stage)",
            attributes: attrs
        )
        recordEvent(event)
    }
}

// MARK: - Legacy Codable Payload (kept for backward compatibility)

/// Batch payload sent to `POST /api/v1/telemetry/inference` (v1 legacy).
struct TelemetryBatchPayload: Codable {
    let modelId: String
    let events: [InferenceTelemetryEvent]

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case events
    }
}

/// A single funnel analytics event (v1 legacy format).
public struct FunnelEvent: Codable, Sendable {
    public let stage: String
    public let success: Bool
    public let source: String
    public let deviceId: String?
    public let modelId: String?
    public let rolloutId: String?
    public let sessionId: String?
    public let failureReason: String?
    public let failureCategory: String?
    public let durationMs: Int?
    public let sdkVersion: String?
    public let platform: String?
    public let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case stage, success, source
        case deviceId = "device_id"
        case modelId = "model_id"
        case rolloutId = "rollout_id"
        case sessionId = "session_id"
        case failureReason = "failure_reason"
        case failureCategory = "failure_category"
        case durationMs = "duration_ms"
        case sdkVersion = "sdk_version"
        case platform, metadata
    }
}

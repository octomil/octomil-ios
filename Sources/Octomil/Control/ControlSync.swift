import Foundation
import os.log

/// Synchronises device control-plane state with the Octomil server.
///
/// Use ``refresh()`` to fetch the latest configuration, feature-flag
/// assignments, and rollout state. The actor serialises concurrent
/// refresh attempts so only one network round-trip is in flight at a time.
///
/// ```swift
/// let result = try await client.control.refresh()
/// if result.assignmentsChanged {
///     // re-evaluate experiment arms
/// }
/// ```
public actor ControlSync {
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "ControlSync")

    /// The most recently fetched sync result, or nil if ``refresh()`` has not been called.
    public private(set) var lastResult: ControlSyncResult?

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Fetches the latest control-plane state from the server.
    ///
    /// - Returns: A ``ControlSyncResult`` describing what changed.
    public func refresh() async throws -> ControlSyncResult {
        let result: ControlSyncResult = try await apiClient.getJSON(
            path: "api/v1/control/sync"
        )
        lastResult = result
        logger.debug("Control sync completed: version=\(result.configVersion) updated=\(result.updated)")
        return result
    }

    // MARK: - Observed State (contract: devices.observed_state, GAP-05)

    /// Reports the device's observed state to the server.
    ///
    /// Posts per-model status (active version, staged versions, errors) and
    /// runtime metadata so the server can reconcile desired vs observed state.
    ///
    /// - Parameter deviceId: The server-assigned device identifier.
    /// - Parameter models: Per-model observed state entries.
    public func reportObservedState(
        deviceId: String,
        models: [ObservedModelEntry] = []
    ) async throws {
        let payload = ObservedStatePayload(
            schemaVersion: "1.4.0",
            deviceId: deviceId,
            reportedAt: ISO8601DateFormatter().string(from: Date()),
            models: models,
            sdkVersion: OctomilVersion.current,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        let _: EmptyResponse = try await apiClient.postJSON(
            path: "api/v1/devices/\(deviceId)/observed-state",
            body: payload
        )
        logger.debug("Observed state reported for device \(deviceId)")
    }

    // MARK: - Desired State (contract: devices.desired_state, GAP-13)

    /// Fetches the server-authoritative desired state for this device.
    ///
    /// - Parameter deviceId: The server-assigned device identifier.
    /// - Returns: The desired state containing target binding, artifacts, and policy.
    public func fetchDesiredState(deviceId: String) async throws -> DesiredStateResponse {
        let result: DesiredStateResponse = try await apiClient.getJSON(
            path: "api/v1/devices/\(deviceId)/desired-state"
        )
        logger.debug("Desired state fetched for device \(deviceId)")
        return result
    }

    // MARK: - Unified Device Sync (contract: devices.sync)

    /// Performs a unified device sync round-trip.
    ///
    /// This combines observed-state reporting and desired-state fetch into a
    /// single server call. New SDK integrations should prefer this over the
    /// separate desired/observed endpoints.
    public func sync(
        deviceId: String,
        modelInventory: [SyncModelInventoryEntry] = [],
        activeVersions: [SyncActiveVersionEntry] = [],
        knownStateVersion: String? = nil,
        appId: String? = nil,
        appVersion: String? = nil,
        availableStorageBytes: Int64? = nil
    ) async throws -> DeviceSyncResponse {
        let payload = DeviceSyncRequest(
            deviceId: deviceId,
            requestedAt: ISO8601DateFormatter().string(from: Date()),
            knownStateVersion: knownStateVersion,
            sdkVersion: OctomilVersion.current,
            platform: "ios",
            appId: appId,
            appVersion: appVersion,
            modelInventory: modelInventory,
            activeVersions: activeVersions,
            availableStorageBytes: availableStorageBytes
        )

        let result: DeviceSyncResponse = try await apiClient.postJSON(
            path: "api/v1/devices/\(deviceId)/sync",
            body: payload
        )
        logger.debug("Unified device sync completed for device \(deviceId)")
        return result
    }

    // MARK: - Heartbeat (contract: control.heartbeat)

    /// Sends a liveness signal to the server.
    ///
    /// Fire-and-forget: this method launches the request in a detached
    /// task and never throws. Callers are not blocked on the response.
    ///
    /// Per the contract:
    /// - Blocking: false
    /// - Idempotent: true
    /// - Failure is non-fatal; errors are silently logged
    /// - Side-effects: updates server-side last-seen timestamp, may extend session TTL
    ///
    /// ```swift
    /// client.control.heartbeat()
    /// ```
    /// Monotonically increasing heartbeat sequence number for telemetry.
    private var heartbeatSequence = 0

    nonisolated public func heartbeat() {
        Task.detached { [apiClient, logger, weak self] in
            // Emit octomil.control.heartbeat telemetry span
            if let self = self {
                let seq = await self.nextHeartbeatSequence()
                TelemetryQueue.shared?.recordEvent(TelemetryEvent(
                    name: SpanName.octomilControlHeartbeat,
                    attributes: [
                        SpanAttribute.heartbeatSequence: .int(seq),
                    ]
                ))
            }

            do {
                let _: HeartbeatAck = try await apiClient.postJSON(
                    path: "api/v1/control/heartbeat",
                    body: EmptyBody()
                )
                logger.debug("Control heartbeat ack received")
            } catch {
                // Contract: SDK MUST NOT surface heartbeat errors to the caller.
                logger.debug("Control heartbeat failed (non-fatal): \(error.localizedDescription)")
            }
        }
    }

    /// Returns the next heartbeat sequence number (actor-isolated).
    private func nextHeartbeatSequence() -> Int {
        let seq = heartbeatSequence
        heartbeatSequence += 1
        return seq
    }
}

// MARK: - Heartbeat internal types

/// Response from ``control.heartbeat``.
struct HeartbeatAck: Decodable, Sendable {
    let ack: Bool
}

/// Empty request body for ``control.heartbeat``.
private struct EmptyBody: Encodable, Sendable {}

/// Empty response for endpoints that return `{}` or `204`.
private struct EmptyResponse: Decodable, Sendable {}

// MARK: - Observed State types (GAP-05)

/// Per-model observed state entry in an observed state report.
public struct ObservedModelEntry: Codable, Sendable {
    public let modelId: String
    public let artifactId: String
    public let artifactVersion: String
    public let status: String
    public let errorCode: String?

    public init(
        modelId: String,
        artifactId: String,
        artifactVersion: String,
        status: String,
        errorCode: String? = nil
    ) {
        self.modelId = modelId
        self.artifactId = artifactId
        self.artifactVersion = artifactVersion
        self.status = status
        self.errorCode = errorCode
    }

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case artifactId = "artifact_id"
        case artifactVersion = "artifact_version"
        case status
        case errorCode = "error_code"
    }
}

/// Payload sent to ``POST /devices/{id}/observed-state``.
struct ObservedStatePayload: Encodable, Sendable {
    let schemaVersion: String
    let deviceId: String
    let reportedAt: String
    let models: [ObservedModelEntry]
    let sdkVersion: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceId = "device_id"
        case reportedAt = "reported_at"
        case models
        case sdkVersion = "sdk_version"
        case osVersion = "os_version"
    }
}

// MARK: - Desired State types (contract 1.12.0)

/// Response from ``GET /devices/{id}/desired-state``.
public struct DesiredStateResponse: Decodable, Sendable {
    public let deviceId: String
    public let desiredStateVersion: Int
    public let models: [DesiredModelEntry]
    public let gcEligibleArtifactIds: [String]

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case desiredStateVersion = "desired_state_version"
        case models
        case gcEligibleArtifactIds = "gc_eligible_artifact_ids"
    }
}

/// Installed model artifact status included in a unified sync request.
public struct SyncModelInventoryEntry: Codable, Sendable {
    public let modelId: String
    public let version: String
    public let artifactId: String?
    public let status: String

    public init(
        modelId: String,
        version: String,
        artifactId: String? = nil,
        status: String
    ) {
        self.modelId = modelId
        self.version = version
        self.artifactId = artifactId
        self.status = status
    }
}

/// Active serving version included in a unified sync request.
public struct SyncActiveVersionEntry: Codable, Sendable {
    public let modelId: String
    public let version: String

    public init(modelId: String, version: String) {
        self.modelId = modelId
        self.version = version
    }
}

/// Request payload for ``POST /api/v1/devices/{id}/sync``.
public struct DeviceSyncRequest: Codable, Sendable {
    public let schemaVersion: String
    public let deviceId: String
    public let requestedAt: String
    public let knownStateVersion: String?
    public let sdkVersion: String?
    public let platform: String?
    public let appId: String?
    public let appVersion: String?
    public let modelInventory: [SyncModelInventoryEntry]
    public let activeVersions: [SyncActiveVersionEntry]
    public let availableStorageBytes: Int64?

    public init(
        schemaVersion: String = "1.12.0",
        deviceId: String,
        requestedAt: String,
        knownStateVersion: String? = nil,
        sdkVersion: String? = nil,
        platform: String? = nil,
        appId: String? = nil,
        appVersion: String? = nil,
        modelInventory: [SyncModelInventoryEntry] = [],
        activeVersions: [SyncActiveVersionEntry] = [],
        availableStorageBytes: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.deviceId = deviceId
        self.requestedAt = requestedAt
        self.knownStateVersion = knownStateVersion
        self.sdkVersion = sdkVersion
        self.platform = platform
        self.appId = appId
        self.appVersion = appVersion
        self.modelInventory = modelInventory
        self.activeVersions = activeVersions
        self.availableStorageBytes = availableStorageBytes
    }
}

/// Response from ``POST /api/v1/devices/{id}/sync``.
public struct DeviceSyncResponse: Decodable, Sendable {
    public let schemaVersion: String
    public let deviceId: String
    public let generatedAt: String?
    public let stateChanged: Bool
    public let models: [DesiredModelEntry]
    public let gcEligibleArtifactIds: [String]
    public let nextPollIntervalSeconds: Int
    public let serverTimestamp: String?
}

// MARK: - Artifact Endpoint Methods

extension ControlSync {

    /// Fetches the file manifest for an artifact.
    public func fetchArtifactManifest(artifactId: String) async throws -> ArtifactManifestResponse {
        try await apiClient.getJSON(path: "api/v1/artifacts/\(artifactId)/manifest")
    }

    /// Fetches presigned download URLs for artifact files.
    public func fetchDownloadUrls(artifactId: String, files: [String]) async throws -> DownloadUrlsResponse {
        let body = DownloadUrlsRequest(files: files)
        return try await apiClient.postJSON(path: "api/v1/artifacts/\(artifactId)/download-urls", body: body)
    }
}

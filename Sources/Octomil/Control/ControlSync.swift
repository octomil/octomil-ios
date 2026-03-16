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
    /// Posts artifact download progress, active model pointer, and runtime
    /// metadata so the server can reconcile desired vs observed state.
    ///
    /// - Parameter deviceId: The server-assigned device identifier.
    /// - Parameter artifactStatuses: Per-artifact status entries.
    public func reportObservedState(
        deviceId: String,
        artifactStatuses: [ArtifactStatusEntry] = []
    ) async throws {
        let payload = ObservedStatePayload(
            schemaVersion: "1.4.0",
            deviceId: deviceId,
            reportedAt: ISO8601DateFormatter().string(from: Date()),
            artifactStatuses: artifactStatuses,
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

/// Per-artifact status entry in an observed state report.
public struct ArtifactStatusEntry: Codable, Sendable {
    public let artifactId: String
    public let status: String
    public let bytesDownloaded: Int?
    public let totalBytes: Int?
    public let errorCode: String?

    public init(
        artifactId: String,
        status: String,
        bytesDownloaded: Int? = nil,
        totalBytes: Int? = nil,
        errorCode: String? = nil
    ) {
        self.artifactId = artifactId
        self.status = status
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.errorCode = errorCode
    }
}

/// Payload sent to ``POST /devices/{id}/observed-state``.
struct ObservedStatePayload: Encodable, Sendable {
    let schemaVersion: String
    let deviceId: String
    let reportedAt: String
    let artifactStatuses: [ArtifactStatusEntry]
    let sdkVersion: String
    let osVersion: String
}

// MARK: - Desired State types (GAP-13)

/// Response from ``GET /devices/{id}/desired-state``.
public struct DesiredStateResponse: Decodable, Sendable {
    public let schemaVersion: String
    public let deviceId: String
    public let generatedAt: String
    public let activeBinding: AnyCodable?
    public let artifacts: [AnyCodable]?
    public let policyConfig: AnyCodable?
    public let gcEligibleArtifactIds: [String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceId = "device_id"
        case generatedAt = "generated_at"
        case activeBinding = "active_binding"
        case artifacts
        case policyConfig = "policy_config"
        case gcEligibleArtifactIds = "gc_eligible_artifact_ids"
    }
}

/// Type-erased Codable wrapper for mixed-type JSON values.
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        // Encoding not needed for response-only types; satisfy Codable requirement.
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

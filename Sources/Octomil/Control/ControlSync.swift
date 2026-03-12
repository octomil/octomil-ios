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
    nonisolated public func heartbeat() {
        Task.detached { [apiClient, logger] in
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
}

// MARK: - Heartbeat internal types

/// Response from ``control.heartbeat``.
struct HeartbeatAck: Decodable, Sendable {
    let ack: Bool
}

/// Empty request body for ``control.heartbeat``.
private struct EmptyBody: Encodable, Sendable {}

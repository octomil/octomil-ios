import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Heartbeat & Device Info

extension OctomilClient {

    // MARK: - Heartbeat

    /// Sends a heartbeat to the server.
    ///
    /// - Parameter availableStorageMb: Current available storage (optional).
    /// - Returns: Heartbeat response.
    /// - Throws: `OctomilError` if heartbeat fails.
    @discardableResult
    public func sendHeartbeat(availableStorageMb: Int? = nil) async throws -> HeartbeatResponse {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        var metadata: [String: String]? = nil
        if let availableStorageMb = availableStorageMb {
            metadata = ["available_storage_mb": String(availableStorageMb)]
        }

        var request = HeartbeatRequest(metadata: metadata)

        // Collect battery state
        #if canImport(UIKit)
        let batteryState = await MainActor.run { () -> (level: Float, state: UIDevice.BatteryState) in
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            let state = UIDevice.current.batteryState
            return (level, state)
        }
        if batteryState.level >= 0 {
            request.batteryPct = Int(batteryState.level * 100)
        }
        request.charging = batteryState.state != .unplugged && batteryState.state != .unknown
        #endif

        // Report available memory
        #if os(iOS) || os(tvOS) || os(watchOS)
        request.availableMemoryMb = Int(os_proc_available_memory() / (1024 * 1024))
        #else
        request.availableMemoryMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        #endif

        return try await apiClient.sendHeartbeat(deviceId: deviceId, request: request)
    }

    /// Starts automatic heartbeat reporting.
    public func startHeartbeat() {
        heartbeatTask?.cancel()

        heartbeatTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                    _ = try await self.sendHeartbeat()
                    if self.configuration.enableLogging {
                        self.logger.debug("Heartbeat sent successfully")
                    }
                } catch {
                    if self.configuration.enableLogging {
                        self.logger.warning("Heartbeat failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Stops automatic heartbeat reporting.
    public func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        emitState(.closed)
    }

    // MARK: - Device Groups

    /// Gets the groups this device belongs to.
    ///
    /// - Returns: List of device groups.
    /// - Throws: `OctomilError` if the request fails.
    public func getGroups() async throws -> [DeviceGroup] {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        return try await apiClient.getDeviceGroups(deviceId: deviceId)
    }

    /// Checks if this device belongs to a specific group.
    ///
    /// - Parameter groupId: The group ID to check.
    /// - Returns: True if device is a member of the group.
    /// - Throws: `OctomilError` if the request fails.
    public func isMemberOf(groupId: String) async throws -> Bool {
        let groups = try await getGroups()
        return groups.contains { $0.id == groupId }
    }

    /// Checks if this device belongs to a group with the given name.
    ///
    /// - Parameter groupName: The group name to check.
    /// - Returns: True if device is a member of a group with that name.
    /// - Throws: `OctomilError` if the request fails.
    public func isMemberOf(groupName: String) async throws -> Bool {
        let groups = try await getGroups()
        return groups.contains { $0.name == groupName }
    }

    /// Gets this device's full information from the server.
    ///
    /// - Returns: Full device information.
    /// - Throws: `OctomilError` if the request fails.
    public func getDeviceInfo() async throws -> DeviceInfo {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        return try await apiClient.getDeviceInfo(deviceId: deviceId)
    }
}

import Foundation

// MARK: - Device Endpoints

extension APIClient {

    /// Registers a device with the server.
    /// - Parameter request: Registration request.
    /// - Returns: Registration response with server-assigned ID.
    public func registerDevice(_ request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/register")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    /// Sends a heartbeat to the server to indicate device is alive.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - request: Heartbeat request with optional status update.
    /// - Returns: Heartbeat response with updated status.
    public func sendHeartbeat(deviceId: String, request: HeartbeatRequest = HeartbeatRequest()) async throws -> HeartbeatResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/heartbeat")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    /// Gets the groups this device belongs to.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: List of device groups.
    public func getDeviceGroups(deviceId: String) async throws -> [DeviceGroup] {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/groups")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let response: DeviceGroupsResponse = try await performRequest(urlRequest)
        return response.groups
    }

    /// Gets device information from server.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: Full device information.
    public func getDeviceInfo(deviceId: String) async throws -> DeviceInfo {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets the device policy for an organization.
    /// - Parameter orgId: Organization identifier.
    /// - Returns: Device policy response.
    public func getDevicePolicy(orgId: String) async throws -> DevicePolicyResponse {
        let url = serverURL.appendingPathComponent("api/v1/settings/org/\(orgId)/device-policy")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }
}

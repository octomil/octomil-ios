import Foundation

// MARK: - Secure Aggregation Endpoints

extension APIClient {

    /// Joins a SecAgg session for a training round.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - roundId: The training round to join.
    /// - Returns: Session details including this client's index.
    public func joinSecAggSession(deviceId: String, roundId: String) async throws -> SecAggSessionResponse {
        let url = serverURL.appendingPathComponent("api/v1/secagg/sessions/join")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: String] = ["device_id": deviceId, "round_id": roundId]
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }

    /// Submits key shares for SecAgg Phase 1.
    /// - Parameter request: Share keys request.
    public func submitSecAggShares(_ request: SecAggShareKeysRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/shares")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: APIEmptyResponse = try await performRequest(urlRequest)
    }

    /// Submits masked model update for SecAgg Phase 2.
    /// - Parameter request: Masked input request.
    public func submitSecAggMaskedInput(_ request: SecAggMaskedInputRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/masked-input")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: APIEmptyResponse = try await performRequest(urlRequest)
    }

    /// Requests unmasking info and submits this client's unmasking shares.
    /// - Parameters:
    ///   - sessionId: SecAgg session identifier.
    ///   - deviceId: Server-assigned device UUID.
    /// - Returns: Unmask response with dropped client indices.
    public func getSecAggUnmaskInfo(sessionId: String, deviceId: String) async throws -> SecAggUnmaskResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/secagg/unmask"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "device_id", value: deviceId)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Submits unmasking data for SecAgg Phase 3.
    /// - Parameter request: Unmask request.
    public func submitSecAggUnmask(_ request: SecAggUnmaskRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/unmask")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: APIEmptyResponse = try await performRequest(urlRequest)
    }
}

import Foundation

public typealias FederationUploadInitiateRequest = [String: AnyCodable]
public typealias FederationUploadInitiateResponse = [String: AnyCodable]
public typealias FederationUploadCompleteRequest = [String: AnyCodable]
public typealias FederationUploadCompleteResponse = [String: AnyCodable]
public typealias FederationHeartbeatResponse = [String: AnyCodable]

/// Contract-aligned federation namespace for round coordination helpers.
public final class FederationClient: @unchecked Sendable {
    private let apiClient: APIClient
    private let deviceIdProvider: @Sendable () -> String?

    public init(
        apiClient: APIClient,
        deviceIdProvider: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceIdProvider = deviceIdProvider
    }

    public func heartbeat(
        roundId: String,
        request: [String: AnyCodable] = [:]
    ) async throws -> FederationHeartbeatResponse {
        var payload = request
        if payload["deviceId"] == nil, let deviceId = deviceIdProvider() {
            payload["deviceId"] = AnyCodable(deviceId)
        }
        return try await apiClient.postJSON(
            path: "api/v1/federation/rounds/\(roundId)/heartbeat",
            body: payload
        )
    }

    public func uploadInitiate(
        roundId: String,
        request: FederationUploadInitiateRequest
    ) async throws -> FederationUploadInitiateResponse {
        try await apiClient.postJSON(
            path: "api/v1/federation/rounds/\(roundId)/updates/initiate",
            body: request
        )
    }

    public func uploadComplete(
        roundId: String,
        uploadId: String,
        request: FederationUploadCompleteRequest
    ) async throws -> FederationUploadCompleteResponse {
        try await apiClient.postJSON(
            path: "api/v1/federation/rounds/\(roundId)/updates/\(uploadId)/complete",
            body: request
        )
    }
}

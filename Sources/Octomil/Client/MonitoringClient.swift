import Foundation

public typealias AlertRule = [String: AnyCodable]
public typealias UpdateAlertRuleRequest = [String: AnyCodable]

/// Contract-aligned monitoring namespace.
public final class MonitoringClient: @unchecked Sendable {
    private let apiClient: APIClient
    private let orgIdProvider: @Sendable () -> String

    public init(
        apiClient: APIClient,
        orgIdProvider: @escaping @Sendable () -> String
    ) {
        self.apiClient = apiClient
        self.orgIdProvider = orgIdProvider
    }

    public func getAlertRule(
        ruleId: String,
        orgId: String? = nil
    ) async throws -> AlertRule {
        try await apiClient.getJSON(
            path: "api/v1/monitoring/alerts/\(ruleId)",
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func updateAlertRule(
        ruleId: String,
        request: UpdateAlertRuleRequest,
        orgId: String? = nil
    ) async throws -> AlertRule {
        try await apiClient.patchJSON(
            path: "api/v1/monitoring/alerts/\(ruleId)",
            body: request,
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func deleteAlertRule(
        ruleId: String,
        orgId: String? = nil
    ) async throws {
        try await apiClient.deleteRequest(
            path: "api/v1/monitoring/alerts/\(ruleId)",
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }
}

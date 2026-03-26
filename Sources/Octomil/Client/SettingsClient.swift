import Foundation

public typealias BillingSession = [String: AnyCodable]
public typealias BillingState = [String: AnyCodable]
public typealias UsageLimits = [String: AnyCodable]
public typealias Integration = [String: AnyCodable]
public typealias IntegrationPatch = [String: AnyCodable]
public typealias IntegrationValidation = [String: AnyCodable]

/// Contract-aligned settings namespace.
public final class SettingsClient: @unchecked Sendable {
    private let apiClient: APIClient
    private let orgIdProvider: @Sendable () -> String

    public init(
        apiClient: APIClient,
        orgIdProvider: @escaping @Sendable () -> String
    ) {
        self.apiClient = apiClient
        self.orgIdProvider = orgIdProvider
    }

    public func createCheckoutSession(
        _ request: [String: AnyCodable],
        orgId: String? = nil
    ) async throws -> BillingSession {
        try await apiClient.postJSON(
            path: "api/v1/settings/billing/checkout",
            body: request,
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func createPortalSession(
        _ request: [String: AnyCodable],
        orgId: String? = nil
    ) async throws -> BillingSession {
        try await apiClient.postJSON(
            path: "api/v1/settings/billing/portal",
            body: request,
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func updateBilling(
        _ request: [String: AnyCodable],
        orgId: String? = nil
    ) async throws -> BillingState {
        try await apiClient.patchJSON(
            path: "api/v1/settings/billing",
            body: request,
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func getUsageLimits(orgId: String? = nil) async throws -> UsageLimits {
        try await apiClient.getJSON(
            path: "api/v1/settings/usage-limits",
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func updateUsageLimits(
        _ request: [String: AnyCodable],
        orgId: String? = nil
    ) async throws -> UsageLimits {
        try await apiClient.putJSON(
            path: "api/v1/settings/usage-limits",
            body: request,
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func getIntegration(
        integrationId: String,
        orgId: String? = nil
    ) async throws -> Integration {
        try await apiClient.getJSON(
            path: "api/v1/settings/integrations/\(integrationId)",
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func updateIntegration(
        integrationId: String,
        request: IntegrationPatch,
        orgId: String? = nil
    ) async throws -> Integration {
        try await apiClient.patchJSON(
            path: "api/v1/settings/integrations/\(integrationId)",
            body: request,
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func deleteIntegration(
        integrationId: String,
        orgId: String? = nil
    ) async throws {
        try await apiClient.deleteRequest(
            path: "api/v1/settings/integrations/\(integrationId)",
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }

    public func validateIntegration(
        integrationId: String,
        orgId: String? = nil
    ) async throws -> IntegrationValidation {
        try await apiClient.postJSON(
            path: "api/v1/settings/integrations/\(integrationId)/validate",
            body: [String: AnyCodable](),
            queryItems: [URLQueryItem(name: "org_id", value: orgId ?? orgIdProvider())]
        )
    }
}

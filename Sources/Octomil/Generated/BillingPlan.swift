// Auto-generated from octomil-contracts. Do not edit.

public struct PlanLimits: Sendable, Equatable {
    public let maxDevices: Int?
    public let maxModels: Int?
    public let maxEnvironments: Int?
    public let storageGb: Int?
    public let requestsMonthly: Int?
    public let trainingRoundsMonthly: Int?
    public let federatedRoundsMonthly: Int?
    public let modelDownloadsMonthly: Int?
    public let modelConversionsMonthly: Int?
    public let dataRetentionDays: Int?
}

public struct PlanFeatures: Sendable, Equatable {
    public let sso: Bool
    public let federatedLearning: Bool
    public let differentialPrivacy: Bool
    public let secureAggregation: Bool
    public let hipaaMode: Bool
    public let advancedMonitoring: Bool
    public let webhooks: Bool
    public let experiments: Bool
    public let rollouts: Bool
    public let scim: Bool
    public let siemExport: Bool
}

public struct PlanPricing: Sendable, Equatable {
    public let monthlyCents: Int?
    public let annualCents: Int?
    public let overagePerDeviceCents: Int?
}

public enum BillingPlan: String, Codable, Sendable {
    case free = "free"
    case team = "team"
    case enterprise = "enterprise"
}

extension BillingPlan {
    public var displayName: String {
        switch self {
        case .free: return "Developer"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        }
    }

    public var limits: PlanLimits {
        switch self {
        case .free: return PlanLimits(maxDevices: 25, maxModels: 3, maxEnvironments: 1, storageGb: 5, requestsMonthly: 100000, trainingRoundsMonthly: 100, federatedRoundsMonthly: 1, modelDownloadsMonthly: 2500, modelConversionsMonthly: 20, dataRetentionDays: 7)
        case .team: return PlanLimits(maxDevices: 1000, maxModels: 20, maxEnvironments: 3, storageGb: 100, requestsMonthly: 1000000, trainingRoundsMonthly: 10000, federatedRoundsMonthly: 10, modelDownloadsMonthly: 50000, modelConversionsMonthly: 500, dataRetentionDays: 90)
        case .enterprise: return PlanLimits(maxDevices: nil, maxModels: nil, maxEnvironments: nil, storageGb: 10000, requestsMonthly: 100000000, trainingRoundsMonthly: nil, federatedRoundsMonthly: nil, modelDownloadsMonthly: nil, modelConversionsMonthly: nil, dataRetentionDays: nil)
        }
    }

    public var features: PlanFeatures {
        switch self {
        case .free: return PlanFeatures(sso: false, federatedLearning: true, differentialPrivacy: false, secureAggregation: false, hipaaMode: false, advancedMonitoring: false, webhooks: false, experiments: true, rollouts: true, scim: false, siemExport: false)
        case .team: return PlanFeatures(sso: true, federatedLearning: true, differentialPrivacy: false, secureAggregation: false, hipaaMode: false, advancedMonitoring: true, webhooks: true, experiments: true, rollouts: true, scim: false, siemExport: false)
        case .enterprise: return PlanFeatures(sso: true, federatedLearning: true, differentialPrivacy: true, secureAggregation: true, hipaaMode: true, advancedMonitoring: true, webhooks: true, experiments: true, rollouts: true, scim: true, siemExport: true)
        }
    }

    public var pricing: PlanPricing {
        switch self {
        case .free: return PlanPricing(monthlyCents: 0, annualCents: 0, overagePerDeviceCents: 0)
        case .team: return PlanPricing(monthlyCents: 120000, annualCents: 1152000, overagePerDeviceCents: 5)
        case .enterprise: return PlanPricing(monthlyCents: nil, annualCents: nil, overagePerDeviceCents: nil)
        }
    }

}


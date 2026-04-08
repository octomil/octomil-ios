import Foundation

// MARK: - Events

/// Event to track on the server.
public struct TrackingEvent: Codable, Sendable {
    /// Event name.
    public let name: String
    /// Event properties.
    public let properties: [String: String]
    /// Timestamp.
    public let timestamp: Date
    /// Device identifier.
    public var deviceId: String?
    /// Model identifier.
    public var modelId: String?
    /// Model version.
    public var version: String?
    /// Event type classification.
    public var eventType: String?
    /// Numeric metrics.
    public var metrics: [String: Double]?
    /// String metadata.
    public var metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case properties
        case timestamp
        case deviceId = "device_id"
        case modelId = "model_id"
        case version
        case eventType = "event_type"
        case metrics
        case metadata
    }

    public init(
        name: String,
        properties: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

// MARK: - Secure Aggregation

/// Response from the server when setting up a SecAgg session.
public struct SecAggSessionResponse: Codable, Sendable {
    /// Server-assigned session identifier.
    public let sessionId: String
    /// Round identifier.
    public let roundId: String
    /// This client's 1-based participant index.
    public let clientIndex: Int
    /// Minimum shares needed for reconstruction.
    public let threshold: Int
    /// Total participants in this session.
    public let totalClients: Int
    /// Privacy budget.
    public let privacyBudget: Double
    /// Key length in bits.
    public let keyLength: Int

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case roundId = "round_id"
        case clientIndex = "client_index"
        case threshold
        case totalClients = "total_clients"
        case privacyBudget = "privacy_budget"
        case keyLength = "key_length"
    }
}

/// Request to submit key shares during SecAgg Phase 1.
public struct SecAggShareKeysRequest: Codable, Sendable {
    /// Session identifier.
    public let sessionId: String
    /// Device identifier.
    public let deviceId: String
    /// Base64-encoded serialized share bundles.
    public let sharesData: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case sharesData = "shares_data"
    }
}

/// Request to submit masked model update during SecAgg Phase 2.
public struct SecAggMaskedInputRequest: Codable, Sendable {
    /// Session identifier.
    public let sessionId: String
    /// Device identifier.
    public let deviceId: String
    /// Base64-encoded masked weight data.
    public let maskedWeightsData: String
    /// Number of training samples used.
    public let sampleCount: Int
    /// Training metrics.
    public let metrics: [String: Double]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case maskedWeightsData = "masked_weights_data"
        case sampleCount = "sample_count"
        case metrics
    }
}

/// Request to submit unmasking shares during SecAgg Phase 3.
public struct SecAggUnmaskRequest: Codable, Sendable {
    /// Session identifier.
    public let sessionId: String
    /// Device identifier.
    public let deviceId: String
    /// Base64-encoded unmasking share data.
    public let unmaskData: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case unmaskData = "unmask_data"
    }
}

/// Server response when requesting unmasking, includes dropped client indices.
public struct SecAggUnmaskResponse: Codable, Sendable {
    /// Indices of clients that dropped out.
    public let droppedClientIndices: [Int]
    /// Whether unmasking is needed.
    public let unmaskingRequired: Bool

    enum CodingKeys: String, CodingKey {
        case droppedClientIndices = "dropped_client_indices"
        case unmaskingRequired = "unmasking_required"
    }
}

// MARK: - Error Response

/// Error response from the server.
///
/// Wire shape: `{"code": "...", "message": "...", "details": {...}, "request_id": "..."}`.
/// Legacy servers may send `detail` instead of `message` (FastAPI convention).
/// `retryable` and `category` are optional derived fields the server may include.
/// Product metadata like `suggested_action` and `fallback_eligible` are NOT on the
/// wire — SDKs derive them locally from the contract classification table.
public struct APIErrorResponse: Codable, Sendable {
    /// Error message (new wire format).
    public let message: String?
    /// Legacy error detail message (FastAPI format).
    public let detail: String?
    /// Canonical error code from the contract (e.g. "model_not_found").
    public let code: String?
    /// Optional structured error details.
    public let details: [String: AnyCodable]?
    /// Server-assigned request identifier for tracing.
    public let requestId: String?
    /// Whether this error is retryable (optional, server-derived from contract).
    public let retryable: Bool?
    /// Error category (optional, server-derived from contract).
    public let category: String?

    enum CodingKeys: String, CodingKey {
        case message
        case detail
        case code
        case details
        case requestId = "request_id"
        case retryable
        case category
    }

    /// Returns the best available human-readable error message.
    /// Prefers `message` (new format) over `detail` (legacy FastAPI format).
    public var displayMessage: String {
        message ?? detail ?? "Unknown error"
    }
}

// MARK: - Round Management

/// A federated learning round returned from the server.
public struct RoundAssignment: Codable, Sendable {
    /// Round UUID.
    public let id: String
    /// Organization ID.
    public let orgId: String
    /// Model ID.
    public let modelId: String
    /// Version ID.
    public let versionId: String
    /// Round state.
    public let state: String
    /// Minimum clients required.
    public let minClients: Int
    /// Maximum clients allowed.
    public let maxClients: Int
    /// Client selection strategy.
    public let clientSelectionStrategy: String
    /// Aggregation type.
    public let aggregationType: String
    /// Round timeout in minutes.
    public let timeoutMinutes: Int
    /// Whether differential privacy is enabled.
    public let differentialPrivacy: Bool
    /// DP epsilon value.
    public let dpEpsilon: Double?
    /// DP delta value.
    public let dpDelta: Double?
    /// Whether secure aggregation is enabled.
    public let secureAggregation: Bool
    /// SecAgg threshold.
    public let secaggThreshold: Int?
    /// Number of selected clients.
    public let selectedClientCount: Int
    /// Number of received updates.
    public let receivedUpdateCount: Int
    /// When the round was created.
    public let createdAt: String
    /// When client selection started.
    public let clientSelectionStartedAt: String?
    /// When aggregation completed.
    public let aggregationCompletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case modelId = "model_id"
        case versionId = "version_id"
        case state
        case minClients = "min_clients"
        case maxClients = "max_clients"
        case clientSelectionStrategy = "client_selection_strategy"
        case aggregationType = "aggregation_type"
        case timeoutMinutes = "timeout_minutes"
        case differentialPrivacy = "differential_privacy"
        case dpEpsilon = "dp_epsilon"
        case dpDelta = "dp_delta"
        case secureAggregation = "secure_aggregation"
        case secaggThreshold = "secagg_threshold"
        case selectedClientCount = "selected_client_count"
        case receivedUpdateCount = "received_update_count"
        case createdAt = "created_at"
        case clientSelectionStartedAt = "client_selection_started_at"
        case aggregationCompletedAt = "aggregation_completed_at"
    }
}

/// Response wrapping a list of rounds.
public struct RoundsListResponse: Codable, Sendable {
    /// List of round assignments.
    public let rounds: [RoundAssignment]
}

// MARK: - Health Check

/// Response from the health check endpoint.
public struct HealthResponse: Codable, Sendable {
    /// Server health status.
    public let status: String
    /// Server version.
    public let version: String?
    /// Server timestamp.
    public let timestamp: String?
}

// MARK: - Device Policy

/// Device policy configuration from organization settings.
public struct DevicePolicyResponse: Codable, Sendable {
    /// Minimum battery threshold for training.
    public let batteryThreshold: Int
    /// Network policy (e.g., "wifi_only", "any").
    public let networkPolicy: String
    /// Sampling policy.
    public let samplingPolicy: String?
    /// Training window.
    public let trainingWindow: String?

    enum CodingKeys: String, CodingKey {
        case batteryThreshold = "battery_threshold"
        case networkPolicy = "network_policy"
        case samplingPolicy = "sampling_policy"
        case trainingWindow = "training_window"
    }
}

// MARK: - Runtime Adaptation

/// Server-side recommendation for compute adaptation.
///
/// Returned by the adaptation endpoint when the device reports its current state.
/// The server may have fleet-wide intelligence about which compute units work
/// best for a given model/device combination.
public struct AdaptationRecommendation: Codable, Sendable {
    /// Recommended compute executor (e.g. "all", "cpuAndGPU", "cpuOnly").
    public let recommendedExecutor: String
    /// Recommended CoreML compute units string.
    public let recommendedComputeUnits: String
    /// Whether inference should be throttled.
    public let throttleInference: Bool
    /// Whether batch sizes should be reduced.
    public let reduceBatchSize: Bool

    enum CodingKeys: String, CodingKey {
        case recommendedExecutor = "recommended_executor"
        case recommendedComputeUnits = "recommended_compute_units"
        case throttleInference = "throttle_inference"
        case reduceBatchSize = "reduce_batch_size"
    }

    public init(
        recommendedExecutor: String,
        recommendedComputeUnits: String,
        throttleInference: Bool,
        reduceBatchSize: Bool
    ) {
        self.recommendedExecutor = recommendedExecutor
        self.recommendedComputeUnits = recommendedComputeUnits
        self.throttleInference = throttleInference
        self.reduceBatchSize = reduceBatchSize
    }
}

/// Server-side fallback recommendation when a model format or executor fails.
///
/// The server tracks failure rates across the fleet and can recommend
/// alternative formats or executors when one fails on a specific device.
public struct FallbackRecommendation: Codable, Sendable {
    /// Alternative model format to try (e.g. "coreml", "onnx").
    public let fallbackFormat: String
    /// Alternative executor to try (e.g. "cpuOnly").
    public let fallbackExecutor: String
    /// Pre-signed URL to download the fallback model variant.
    public let downloadURL: String
    /// Optional runtime configuration for the fallback.
    public let runtimeConfig: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case fallbackFormat = "fallback_format"
        case fallbackExecutor = "fallback_executor"
        case downloadURL = "download_url"
        case runtimeConfig = "runtime_config"
    }

    public init(
        fallbackFormat: String,
        fallbackExecutor: String,
        downloadURL: String,
        runtimeConfig: [String: AnyCodable]? = nil
    ) {
        self.fallbackFormat = fallbackFormat
        self.fallbackExecutor = fallbackExecutor
        self.downloadURL = downloadURL
        self.runtimeConfig = runtimeConfig
    }
}

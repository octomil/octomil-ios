import Foundation

// MARK: - Training

/// Configuration for a training round.
public struct TrainingConfig: Codable, Sendable {
    /// Number of local epochs.
    public let epochs: Int
    /// Batch size for training.
    public let batchSize: Int
    /// Learning rate.
    public let learningRate: Double
    /// Whether to shuffle data.
    public let shuffle: Bool

    public init(
        epochs: Int = 1,
        batchSize: Int = 32,
        learningRate: Double = 0.001,
        shuffle: Bool = true
    ) {
        self.epochs = epochs
        self.batchSize = batchSize
        self.learningRate = learningRate
        self.shuffle = shuffle
    }

    /// Default training configuration.
    public static let standard = TrainingConfig()
}

/// Result of a training round.
public struct TrainingResult: Codable, Sendable {
    /// Number of samples used for training.
    public let sampleCount: Int
    /// Training loss.
    public let loss: Double?
    /// Training accuracy if applicable.
    public let accuracy: Double?
    /// Time taken for training in seconds.
    public let trainingTime: TimeInterval
    /// Additional metrics.
    public let metrics: [String: Double]

    enum CodingKeys: String, CodingKey {
        case sampleCount = "sample_count"
        case loss
        case accuracy
        case trainingTime = "training_time"
        case metrics
    }
}

/// Result of participating in a federated round.
public struct RoundResult: Codable, Sendable {
    /// Round identifier.
    public let roundId: String
    /// Training result.
    public let trainingResult: TrainingResult
    /// Whether weights were uploaded successfully.
    public let uploadSucceeded: Bool
    /// Timestamp of completion.
    public let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case trainingResult = "training_result"
        case uploadSucceeded = "upload_succeeded"
        case completedAt = "completed_at"
    }
}

/// Weight update to be uploaded to server.
public struct WeightUpdate: Codable, Sendable {
    /// Model identifier.
    public let modelId: String
    /// Model version.
    public let version: String
    /// Server-assigned device UUID (optional).
    public let deviceId: String?
    /// Compressed weight delta.
    public let weightsData: Data
    /// Number of samples used.
    public let sampleCount: Int
    /// Training metrics.
    public let metrics: [String: Double]
    /// Differential privacy metadata (nil if DP was not applied).
    public let dpMetadata: DPMetadata?

    /// Differential privacy metadata for a weight upload.
    public struct DPMetadata: Codable, Sendable {
        /// Epsilon used for this update.
        public let epsilonUsed: Double?
        /// Noise scale (sigma) applied.
        public let noiseScale: Double?
        /// Noise mechanism used ("gaussian" or "laplace").
        public let mechanism: String?
        /// L2 clipping norm used.
        public let clippingNorm: Double?

        public init(epsilonUsed: Double? = nil, noiseScale: Double? = nil, mechanism: String? = nil, clippingNorm: Double? = nil) {
            self.epsilonUsed = epsilonUsed
            self.noiseScale = noiseScale
            self.mechanism = mechanism
            self.clippingNorm = clippingNorm
        }
    }

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case deviceId = "device_id"
        case weightsData = "weights_data"
        case sampleCount = "sample_count"
        case metrics
        case dpEpsilonUsed = "dp_epsilon_used"
        case dpNoiseScale = "dp_noise_scale"
        case dpMechanism = "dp_mechanism"
        case dpClippingNorm = "dp_clipping_norm"
    }

    public init(
        modelId: String,
        version: String,
        deviceId: String?,
        weightsData: Data,
        sampleCount: Int,
        metrics: [String: Double],
        dpMetadata: DPMetadata? = nil
    ) {
        self.modelId = modelId
        self.version = version
        self.deviceId = deviceId
        self.weightsData = weightsData
        self.sampleCount = sampleCount
        self.metrics = metrics
        self.dpMetadata = dpMetadata
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(deviceId, forKey: .deviceId)
        try container.encode(weightsData, forKey: .weightsData)
        try container.encode(sampleCount, forKey: .sampleCount)
        try container.encode(metrics, forKey: .metrics)
        try container.encodeIfPresent(dpMetadata?.epsilonUsed, forKey: .dpEpsilonUsed)
        try container.encodeIfPresent(dpMetadata?.noiseScale, forKey: .dpNoiseScale)
        try container.encodeIfPresent(dpMetadata?.mechanism, forKey: .dpMechanism)
        try container.encodeIfPresent(dpMetadata?.clippingNorm, forKey: .dpClippingNorm)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try container.decode(String.self, forKey: .modelId)
        version = try container.decode(String.self, forKey: .version)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        weightsData = try container.decode(Data.self, forKey: .weightsData)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        metrics = try container.decode([String: Double].self, forKey: .metrics)
        let epsilonUsed = try container.decodeIfPresent(Double.self, forKey: .dpEpsilonUsed)
        let noiseScale = try container.decodeIfPresent(Double.self, forKey: .dpNoiseScale)
        let mechanism = try container.decodeIfPresent(String.self, forKey: .dpMechanism)
        let clippingNorm = try container.decodeIfPresent(Double.self, forKey: .dpClippingNorm)
        if epsilonUsed != nil || noiseScale != nil || mechanism != nil || clippingNorm != nil {
            dpMetadata = DPMetadata(epsilonUsed: epsilonUsed, noiseScale: noiseScale, mechanism: mechanism, clippingNorm: clippingNorm)
        } else {
            dpMetadata = nil
        }
    }
}

// MARK: - Gradient Submission

/// Request body for submitting gradients.
public struct GradientUpdateRequest: Codable, Sendable {
    /// Device identifier.
    public let deviceId: String
    /// Model identifier.
    public let modelId: String
    /// Model version.
    public let version: String
    /// Round identifier.
    public let roundId: String
    /// Path to stored gradients (optional).
    public let gradientsPath: String?
    /// Number of training samples.
    public let numSamples: Int
    /// Training time in milliseconds.
    public let trainingTimeMs: Int64
    /// Training metrics.
    public let metrics: GradientTrainingMetrics

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelId = "model_id"
        case version
        case roundId = "round_id"
        case gradientsPath = "gradients_path"
        case numSamples = "num_samples"
        case trainingTimeMs = "training_time_ms"
        case metrics
    }
}

/// Training metrics submitted with gradient updates.
public struct GradientTrainingMetrics: Codable, Sendable {
    /// Training loss.
    public let loss: Double
    /// Training accuracy.
    public let accuracy: Double?
    /// Number of training batches.
    public let numBatches: Int
    /// Learning rate used.
    public let learningRate: Double?
    /// Custom metrics.
    public let customMetrics: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case loss
        case accuracy
        case numBatches = "num_batches"
        case learningRate = "learning_rate"
        case customMetrics = "custom_metrics"
    }
}

/// Response from gradient submission.
public struct GradientUpdateResponse: Codable, Sendable {
    /// Whether the update was accepted.
    public let accepted: Bool
    /// Round identifier.
    public let roundId: String
    /// Optional message.
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case accepted
        case roundId = "round_id"
        case message
    }
}

import Foundation

// MARK: - Model Metadata

/// Metadata about a model version.
public struct ModelMetadata: Codable, Sendable {
    /// Model identifier.
    public let modelId: String
    /// Version string.
    public let version: String
    /// SHA256 checksum of the model file.
    public let checksum: String
    /// File size in bytes.
    public let fileSize: UInt64
    /// When this version was created.
    public let createdAt: Date
    /// Model format.
    public let format: String
    /// Whether training is supported.
    public let supportsTraining: Bool
    /// Model description.
    public let description: String?
    /// Input schema.
    public let inputSchema: [String: String]?
    /// Output schema.
    public let outputSchema: [String: String]?
    /// Server-extracted model contract with input/output tensor specifications.
    public let serverContract: ServerModelContract?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case checksum
        case fileSize = "file_size"
        case createdAt = "created_at"
        case format
        case supportsTraining = "supports_training"
        case description
        case inputSchema = "input_schema"
        case outputSchema = "output_schema"
        case serverContract = "server_contract"
    }

    public init(
        modelId: String,
        version: String,
        checksum: String,
        fileSize: UInt64,
        createdAt: Date,
        format: String,
        supportsTraining: Bool,
        description: String?,
        inputSchema: [String: String]?,
        outputSchema: [String: String]?,
        serverContract: ServerModelContract? = nil
    ) {
        self.modelId = modelId
        self.version = version
        self.checksum = checksum
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.format = format
        self.supportsTraining = supportsTraining
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.serverContract = serverContract
    }
}

/// Response schema for a model version (server API).
public struct ModelVersionResponse: Codable, Sendable {
    public let modelId: String
    public let version: String
    public let checksum: String
    public let sizeBytes: UInt64
    public let format: String
    public let description: String?
    public let createdAt: Date
    public let metrics: [String: AnyCodable]?
    /// Server-extracted model contract with input/output tensor specifications.
    public let modelContract: ServerModelContract?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case checksum
        case sizeBytes = "size_bytes"
        case format
        case description
        case createdAt = "created_at"
        case metrics
        case modelContract = "model_contract"
    }
}

// AnyCodable is defined in Chat/Tool.swift and shared across the module.

/// Information about a model update.
public struct ModelUpdateInfo: Codable, Sendable {
    /// The new version available.
    public let newVersion: String
    /// Current version on device.
    public let currentVersion: String
    /// Whether update is required.
    public let isRequired: Bool
    /// Release notes for the update.
    public let releaseNotes: String?
    /// Size of the update in bytes.
    public let updateSize: UInt64

    enum CodingKeys: String, CodingKey {
        case newVersion = "new_version"
        case currentVersion = "current_version"
        case isRequired = "is_required"
        case releaseNotes = "release_notes"
        case updateSize = "update_size"
    }
}

// MARK: - Version Resolution

/// Response from version resolution endpoint.
public struct VersionResolutionResponse: Codable, Sendable {
    /// Resolved version string.
    public let version: String
    /// Source of the resolution.
    public let source: String
    /// Experiment ID if applicable.
    public let experimentId: String?
    /// Rollout ID if applicable.
    public let rolloutId: Int?
    /// Device bucket for debugging.
    public let deviceBucket: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case experimentId = "experiment_id"
        case rolloutId = "rollout_id"
        case deviceBucket = "device_bucket"
    }
}

/// Request body for model format resolution.
public struct ModelResolveRequest: Codable, Sendable {
    public let platform: String
    public let model: String?
    public let manufacturer: String?
    public let cpuArchitecture: String?
    public let osVersion: String?
    public let totalMemoryMb: Int?
    public let gpuAvailable: Bool
    public let npuAvailable: Bool
    public let supportedRuntimes: [String]
    public let computeUnits: String?

    public init(
        platform: String,
        model: String?,
        manufacturer: String?,
        cpuArchitecture: String?,
        osVersion: String?,
        totalMemoryMb: Int?,
        gpuAvailable: Bool,
        npuAvailable: Bool,
        supportedRuntimes: [String],
        computeUnits: String?
    ) {
        self.platform = platform
        self.model = model
        self.manufacturer = manufacturer
        self.cpuArchitecture = cpuArchitecture
        self.osVersion = osVersion
        self.totalMemoryMb = totalMemoryMb
        self.gpuAvailable = gpuAvailable
        self.npuAvailable = npuAvailable
        self.supportedRuntimes = supportedRuntimes
        self.computeUnits = computeUnits
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case model
        case manufacturer
        case cpuArchitecture = "cpu_architecture"
        case osVersion = "os_version"
        case totalMemoryMb = "total_memory_mb"
        case gpuAvailable = "gpu_available"
        case npuAvailable = "npu_available"
        case supportedRuntimes = "supported_runtimes"
        case computeUnits = "compute_units"
    }
}

/// Response from POST /api/v1/models/{model_id}/versions/{version}/resolve.
public struct ModelResolveResponse: Codable, Sendable {
    public let modelId: String
    public let version: String
    public let format: String
    public let quantization: String?
    public let executor: String?
    public let downloadUrl: String
    public let availableFormats: [String]

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case format
        case quantization
        case executor
        case downloadUrl = "download_url"
        case availableFormats = "available_formats"
    }
}

/// Response with download URL.
public struct DownloadURLResponse: Codable, Sendable {
    /// Pre-signed download URL.
    public let url: String
    /// URL expiration time.
    public let expiresAt: Date
    /// File checksum for verification.
    public let checksum: String
    /// File size in bytes.
    public let fileSize: UInt64
    /// Quantization type (e.g., "float32", "float16", "int8").
    public let quantization: String?
    /// Recommended delegates for this model variant.
    public let recommendedDelegates: [String]?
    /// Model input tensor shape.
    public let inputShape: [Int]?
    /// Model output tensor shape.
    public let outputShape: [Int]?
    /// Whether the model includes a training signature.
    public let hasTrainingSignature: Bool?

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
        case checksum
        case fileSize = "file_size"
        case quantization
        case recommendedDelegates = "recommended_delegates"
        case inputShape = "input_shape"
        case outputShape = "output_shape"
        case hasTrainingSignature = "has_training_signature"
    }
}

// MARK: - Model Metadata (full model)

/// Response from the model metadata endpoint.
public struct ModelResponse: Codable, Sendable {
    /// Model UUID.
    public let id: String
    /// Organization ID.
    public let orgId: String
    /// Model name.
    public let name: String
    /// Model framework.
    public let framework: String
    /// Model use case.
    public let useCase: String
    /// Optional description.
    public let description: String?
    /// Number of versions.
    public let versionCount: Int
    /// When created.
    public let createdAt: String
    /// When last updated.
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case name
        case framework
        case useCase = "use_case"
        case description
        case versionCount = "version_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

import Foundation

// MARK: - Device Registration

/// Request body for device registration.
/// Aligns with server's DeviceRegistrationRequest schema.
public struct DeviceRegistrationRequest: Codable, Sendable {
    /// Client-provided device identifier (e.g., IDFV on iOS).
    public let deviceIdentifier: String
    /// Organization identifier.
    public let orgId: String
    /// Device platform (ios, android, python).
    public let platform: String
    /// Operating system version.
    public let osVersion: String?
    /// Octomil SDK version.
    public let sdkVersion: String?
    /// Host application version.
    public let appVersion: String?
    /// Device hardware info.
    public let deviceInfo: DeviceInfoRequest?
    /// Device locale (e.g., "en_US").
    public let locale: String?
    /// Device region/country code.
    public let region: String?
    /// Device timezone.
    public let timezone: String?
    /// Additional device metadata.
    public let metadata: [String: String]?
    /// ML-specific capabilities.
    public let capabilities: DeviceCapabilities?

    // Flat hardware fields (server reads these directly)
    /// Device manufacturer (e.g., "Apple").
    public let manufacturer: String?
    /// Device model identifier (e.g., "iPhone16,1").
    public let model: String?
    /// CPU architecture (e.g., "arm64").
    public let cpuArchitecture: String?
    /// Whether GPU/NPU is available.
    public let gpuAvailable: Bool?
    /// Total RAM in megabytes.
    public let totalMemoryMb: Int?
    /// Available storage in megabytes.
    public let availableStorageMb: Int?
    /// Battery percentage (0-100).
    public let batteryPct: Int?
    /// Whether device is charging.
    public let charging: Bool?

    enum CodingKeys: String, CodingKey {
        case deviceIdentifier = "device_identifier"
        case orgId = "org_id"
        case platform
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case appVersion = "app_version"
        case deviceInfo = "device_info"
        case locale
        case region
        case timezone
        case metadata
        case capabilities
        case manufacturer
        case model
        case cpuArchitecture = "cpu_architecture"
        case gpuAvailable = "gpu_available"
        case totalMemoryMb = "total_memory_mb"
        case availableStorageMb = "available_storage_mb"
        case batteryPct = "battery_pct"
        case charging
    }
}

/// Device hardware info (nested under device_info).
public struct DeviceInfoRequest: Codable, Sendable {
    /// Device manufacturer (e.g., "Apple").
    public let manufacturer: String?
    /// Device model (e.g., "iPhone 15").
    public let model: String?
    /// CPU architecture (e.g., "arm64").
    public let cpuArchitecture: String?
    /// Whether GPU/NPU is available.
    public let gpuAvailable: Bool
    /// Total RAM in megabytes.
    public let totalMemoryMb: Int?
    /// Available storage in megabytes.
    public let availableStorageMb: Int?

    enum CodingKeys: String, CodingKey {
        case manufacturer
        case model
        case cpuArchitecture = "cpu_architecture"
        case gpuAvailable = "gpu_available"
        case totalMemoryMb = "total_memory_mb"
        case availableStorageMb = "available_storage_mb"
    }
}

/// Device capabilities for ML operations.
public struct DeviceCapabilities: Codable, Sendable {
    /// Whether device supports on-device training.
    public let supportsTraining: Bool
    /// CoreML version available (iOS only).
    public let coremlVersion: String?
    /// Whether Neural Engine is available.
    public let hasNeuralEngine: Bool
    /// Maximum batch size supported.
    public let maxBatchSize: Int?
    /// Supported model formats.
    public let supportedFormats: [String]?

    enum CodingKeys: String, CodingKey {
        case supportsTraining = "supports_training"
        case coremlVersion = "coreml_version"
        case hasNeuralEngine = "has_neural_engine"
        case maxBatchSize = "max_batch_size"
        case supportedFormats = "supported_formats"
    }

    public init(
        supportsTraining: Bool = true,
        coremlVersion: String? = nil,
        hasNeuralEngine: Bool = false,
        maxBatchSize: Int? = nil,
        supportedFormats: [String]? = nil
    ) {
        self.supportsTraining = supportsTraining
        self.coremlVersion = coremlVersion
        self.hasNeuralEngine = hasNeuralEngine
        self.maxBatchSize = maxBatchSize
        self.supportedFormats = supportedFormats
    }
}

/// Response from device registration.
public struct DeviceRegistrationResponse: Codable, Sendable {
    /// Server-assigned UUID for this device.
    public let id: String
    /// Client-provided device identifier.
    public let deviceIdentifier: String
    /// Organization identifier.
    public let orgId: String
    /// Device status.
    public let status: String
    /// When the device was registered.
    public let registeredAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case orgId = "org_id"
        case status
        case registeredAt = "registered_at"
    }
}

// MARK: - Device Heartbeat

/// Request body for device heartbeat.
public struct HeartbeatRequest: Codable, Sendable {
    /// Optional metadata to merge with existing device metadata.
    public let metadata: [String: String]?
    /// SDK version.
    public var sdkVersion: String?
    /// OS version.
    public var osVersion: String?
    /// App version.
    public var appVersion: String?
    /// Battery percentage (0-100).
    public var batteryPct: Int?
    /// Whether device is charging.
    public var charging: Bool?
    /// Available storage in MB.
    public var availableStorageMb: Int?
    /// Available memory in MB.
    public var availableMemoryMb: Int?
    /// Network type (e.g., "wifi", "cellular").
    public var networkType: String?

    enum CodingKeys: String, CodingKey {
        case metadata
        case sdkVersion = "sdk_version"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case batteryPct = "battery_pct"
        case charging
        case availableStorageMb = "available_storage_mb"
        case availableMemoryMb = "available_memory_mb"
        case networkType = "network_type"
    }

    public init(metadata: [String: String]? = nil) {
        self.metadata = metadata
    }
}

/// Response from device heartbeat.
public struct HeartbeatResponse: Codable, Sendable {
    /// Device ID.
    public let id: String
    /// Client device identifier.
    public let deviceIdentifier: String
    /// Device status after heartbeat.
    public let status: String
    /// Last heartbeat timestamp.
    public let lastHeartbeat: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case status
        case lastHeartbeat = "last_heartbeat"
    }
}

// MARK: - Device Groups

/// A device group for targeting.
public struct DeviceGroup: Codable, Sendable {
    /// Group UUID.
    public let id: String
    /// Group name.
    public let name: String
    /// Optional description.
    public let description: String?
    /// Group type (static, dynamic, hybrid).
    public let groupType: String
    /// Whether group is active.
    public let isActive: Bool
    /// Number of devices in group.
    public let deviceCount: Int
    /// Group tags.
    public let tags: [String]?
    /// When group was created.
    public let createdAt: Date
    /// When group was last updated.
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case groupType = "group_type"
        case isActive = "is_active"
        case deviceCount = "device_count"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response containing device's group memberships.
public struct DeviceGroupsResponse: Codable, Sendable {
    /// List of groups device belongs to.
    public let groups: [DeviceGroup]
    /// Total count of groups.
    public let count: Int?
}

// MARK: - Device Info

/// Full device information from server.
public struct DeviceInfo: Codable, Sendable {
    /// Server-assigned UUID.
    public let id: String
    /// Client-provided device identifier.
    public let deviceIdentifier: String
    /// Organization ID.
    public let orgId: String
    /// Platform.
    public let platform: String
    /// OS version.
    public let osVersion: String?
    /// SDK version.
    public let sdkVersion: String?
    /// App version.
    public let appVersion: String?
    /// Status.
    public let status: String
    /// Manufacturer.
    public let manufacturer: String?
    /// Model.
    public let model: String?
    /// CPU architecture.
    public let cpuArchitecture: String?
    /// GPU available.
    public let gpuAvailable: Bool
    /// Total memory MB.
    public let totalMemoryMb: Int?
    /// Available storage MB.
    public let availableStorageMb: Int?
    /// Locale.
    public let locale: String?
    /// Region.
    public let region: String?
    /// Timezone.
    public let timezone: String?
    /// Last heartbeat.
    public let lastHeartbeat: Date?
    /// Heartbeat interval.
    public let heartbeatIntervalSeconds: Int
    /// Capabilities.
    public let capabilities: [String: String]?
    /// Created at.
    public let createdAt: Date
    /// Updated at.
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case orgId = "org_id"
        case platform
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case appVersion = "app_version"
        case status
        case manufacturer
        case model
        case cpuArchitecture = "cpu_architecture"
        case gpuAvailable = "gpu_available"
        case totalMemoryMb = "total_memory_mb"
        case availableStorageMb = "available_storage_mb"
        case locale
        case region
        case timezone
        case lastHeartbeat = "last_heartbeat"
        case heartbeatIntervalSeconds = "heartbeat_interval_seconds"
        case capabilities
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

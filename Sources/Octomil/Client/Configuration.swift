import Foundation

/// Configuration options for the Octomil SDK.
public struct OctomilConfiguration: Sendable {

    // MARK: - Sub-configurations

    /// Network-related settings for API communication.
    public struct NetworkPolicy: Sendable {
        /// Maximum number of retry attempts for failed requests.
        public let maxRetryAttempts: Int
        /// Timeout interval for API requests in seconds.
        public let requestTimeout: TimeInterval
        /// Timeout interval for model downloads in seconds.
        public let downloadTimeout: TimeInterval
        /// Whether to require WiFi for model downloads.
        public let requireWiFiForDownload: Bool

        public init(
            maxRetryAttempts: Int = 3,
            requestTimeout: TimeInterval = 30,
            downloadTimeout: TimeInterval = 300,
            requireWiFiForDownload: Bool = false
        ) {
            self.maxRetryAttempts = maxRetryAttempts
            self.requestTimeout = requestTimeout
            self.downloadTimeout = downloadTimeout
            self.requireWiFiForDownload = requireWiFiForDownload
        }
    }

    /// Logging-related settings.
    public struct LoggingPolicy: Sendable {
        /// Whether to enable debug logging.
        public let enableLogging: Bool
        /// Log level for SDK operations.
        public let logLevel: LogLevel

        public init(
            enableLogging: Bool = false,
            logLevel: LogLevel = .info
        ) {
            self.enableLogging = enableLogging
            self.logLevel = logLevel
        }
    }

    /// Training-related device constraints.
    public struct TrainingPolicy: Sendable {
        /// Whether to require charging for background training.
        public let requireChargingForTraining: Bool
        /// Minimum battery level required for background training (0.0 - 1.0).
        public let minimumBatteryLevel: Float

        public init(
            requireChargingForTraining: Bool = true,
            minimumBatteryLevel: Float = 0.2
        ) {
            self.requireChargingForTraining = requireChargingForTraining
            self.minimumBatteryLevel = minimumBatteryLevel
        }
    }

    // MARK: - Stored Properties

    /// Network policy configuration.
    public let network: NetworkPolicy

    /// Logging configuration.
    public let logging: LoggingPolicy

    /// Maximum size of the model cache in bytes.
    public let maxCacheSize: UInt64

    /// Whether to automatically check for model updates.
    public let autoCheckUpdates: Bool

    /// Interval for checking model updates in seconds.
    public let updateCheckInterval: TimeInterval

    /// Training device constraints.
    public let training: TrainingPolicy

    /// Privacy configuration for upload behavior and differential privacy.
    public let privacyConfiguration: PrivacyConfiguration

    /// Whether to allow training when the model lacks an updatable/training signature.
    ///
    /// When `false` (default), calling ``OctomilClient/train`` on a non-updatable model
    /// throws ``MissingTrainingSignatureError``.
    /// When `true`, training proceeds in degraded mode (forward-pass only, no gradient updates)
    /// and ``TrainingOutcome/degraded`` is set to `true`.
    public let allowDegradedTraining: Bool

    /// SHA-256 hashes of pinned server public keys (base64-encoded).
    /// When non-empty, the SDK validates the server certificate against these pins.
    /// Leave empty to use system default certificate validation.
    public let pinnedCertificateHashes: [String]

    // MARK: - Backward-Compatible Accessors

    /// Maximum number of retry attempts for failed requests.
    public var maxRetryAttempts: Int { network.maxRetryAttempts }

    /// Timeout interval for API requests in seconds.
    public var requestTimeout: TimeInterval { network.requestTimeout }

    /// Timeout interval for model downloads in seconds.
    public var downloadTimeout: TimeInterval { network.downloadTimeout }

    /// Whether to require WiFi for model downloads.
    public var requireWiFiForDownload: Bool { network.requireWiFiForDownload }

    /// Whether to enable debug logging.
    public var enableLogging: Bool { logging.enableLogging }

    /// Log level for SDK operations.
    public var logLevel: LogLevel { logging.logLevel }

    /// Whether to require charging for background training.
    public var requireChargingForTraining: Bool { training.requireChargingForTraining }

    /// Minimum battery level required for background training (0.0 - 1.0).
    public var minimumBatteryLevel: Float { training.minimumBatteryLevel }

    // MARK: - Log Level

    /// Log levels for SDK operations.
    public enum LogLevel: Int, Sendable {
        case none = 0
        case error = 1
        case warning = 2
        case info = 3
        case debug = 4
        case verbose = 5
    }

    // MARK: - Initialization

    /// Creates a new configuration with the specified options.
    /// - Parameters:
    ///   - network: Network policy configuration.
    ///   - logging: Logging configuration.
    ///   - maxCacheSize: Maximum size of the model cache in bytes.
    ///   - autoCheckUpdates: Whether to automatically check for model updates.
    ///   - updateCheckInterval: Interval for checking model updates in seconds.
    ///   - training: Training device constraints.
    ///   - privacyConfiguration: Privacy configuration for uploads and differential privacy.
    public init(
        network: NetworkPolicy = NetworkPolicy(),
        logging: LoggingPolicy = LoggingPolicy(),
        maxCacheSize: UInt64 = 500 * 1024 * 1024, // 500 MB
        autoCheckUpdates: Bool = true,
        updateCheckInterval: TimeInterval = 3600, // 1 hour
        training: TrainingPolicy = TrainingPolicy(),
        privacyConfiguration: PrivacyConfiguration = .standard,
        allowDegradedTraining: Bool = false,
        pinnedCertificateHashes: [String] = []
    ) {
        self.network = network
        self.logging = logging
        self.maxCacheSize = maxCacheSize
        self.autoCheckUpdates = autoCheckUpdates
        self.updateCheckInterval = updateCheckInterval
        self.training = training
        self.privacyConfiguration = privacyConfiguration
        self.allowDegradedTraining = allowDegradedTraining
        self.pinnedCertificateHashes = pinnedCertificateHashes
    }

    // MARK: - Presets

    /// Default configuration suitable for most use cases.
    public static let standard = OctomilConfiguration()

    /// Configuration optimized for development and testing.
    public static let development = OctomilConfiguration(
        network: NetworkPolicy(
            maxRetryAttempts: 1,
            requestTimeout: 60,
            downloadTimeout: 600,
            requireWiFiForDownload: false
        ),
        logging: LoggingPolicy(
            enableLogging: true,
            logLevel: .debug
        ),
        maxCacheSize: 1024 * 1024 * 1024, // 1 GB
        autoCheckUpdates: true,
        updateCheckInterval: 300, // 5 minutes
        training: TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.1
        )
    )

    /// Configuration optimized for production with conservative settings.
    public static let production = OctomilConfiguration(
        network: NetworkPolicy(
            maxRetryAttempts: 5,
            requestTimeout: 30,
            downloadTimeout: 300,
            requireWiFiForDownload: true
        ),
        logging: LoggingPolicy(
            enableLogging: false,
            logLevel: .error
        ),
        maxCacheSize: 200 * 1024 * 1024, // 200 MB
        autoCheckUpdates: true,
        updateCheckInterval: 86400, // 24 hours
        training: TrainingPolicy(
            requireChargingForTraining: true,
            minimumBatteryLevel: 0.3
        )
    )
}

// MARK: - Background Constraints

/// Constraints for background training operations.
public struct BackgroundConstraints: Sendable {

    /// Whether WiFi connection is required.
    public let requiresWiFi: Bool

    /// Whether device must be charging.
    public let requiresCharging: Bool

    /// Minimum battery level (0.0 - 1.0).
    public let minimumBatteryLevel: Float

    /// Maximum time allowed for the background task in seconds.
    public let maxExecutionTime: TimeInterval

    /// Creates new background constraints.
    /// - Parameters:
    ///   - requiresWiFi: Whether WiFi connection is required.
    ///   - requiresCharging: Whether device must be charging.
    ///   - minimumBatteryLevel: Minimum battery level (0.0 - 1.0).
    ///   - maxExecutionTime: Maximum time allowed for the background task.
    public init(
        requiresWiFi: Bool = true,
        requiresCharging: Bool = true,
        minimumBatteryLevel: Float = 0.2,
        maxExecutionTime: TimeInterval = 300
    ) {
        self.requiresWiFi = requiresWiFi
        self.requiresCharging = requiresCharging
        self.minimumBatteryLevel = minimumBatteryLevel
        self.maxExecutionTime = maxExecutionTime
    }

    /// Default constraints suitable for most use cases.
    public static let standard = BackgroundConstraints()

    /// Relaxed constraints for development.
    public static let relaxed = BackgroundConstraints(
        requiresWiFi: false,
        requiresCharging: false,
        minimumBatteryLevel: 0.1,
        maxExecutionTime: 600
    )
}

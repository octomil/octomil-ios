import Foundation

/// Configuration for an ``OctomilWrappedModel``.
///
/// Controls validation, telemetry collection, and OTA update behaviour
/// when wrapping a CoreML ``MLModel`` with ``OctomilCoreML/wrap(_:modelId:config:)``.
///
/// ```swift
/// var config = OctomilWrapperConfig.default
/// config.telemetryEnabled = false  // disable for local-only usage
/// let model = try OctomilCoreML.wrap(coreModel, modelId: "classifier", config: config)
/// ```
public struct OctomilWrapperConfig: Sendable {

    /// Shared default configuration.
    public static let `default` = OctomilWrapperConfig()

    // MARK: - Validation

    /// Whether to validate inputs against the server model contract before
    /// each prediction.  When no contract is available validation is skipped
    /// regardless of this flag.
    public var validateInputs: Bool

    // MARK: - Telemetry

    /// Whether to record and report inference telemetry events.
    public var telemetryEnabled: Bool

    /// Maximum number of events to buffer before flushing to the server.
    public var telemetryBatchSize: Int

    /// Maximum interval (seconds) between automatic flushes.
    public var telemetryFlushInterval: TimeInterval

    // MARK: - OTA Updates

    /// Whether to check for over-the-air model updates when the wrapper
    /// is created.  The check runs asynchronously and never blocks the
    /// caller.
    public var otaUpdatesEnabled: Bool

    // MARK: - Server

    /// Base URL of the Octomil server.  Required for telemetry and OTA.
    /// When `nil`, network features are disabled silently.
    public var serverURL: URL?

    /// API key used to authenticate telemetry and OTA requests.
    public var apiKey: String?

    // MARK: - Init

    /// Creates a wrapper configuration with the given options.
    public init(
        validateInputs: Bool = true,
        telemetryEnabled: Bool = true,
        telemetryBatchSize: Int = 50,
        telemetryFlushInterval: TimeInterval = 30,
        otaUpdatesEnabled: Bool = true,
        serverURL: URL? = nil,
        apiKey: String? = nil
    ) {
        self.validateInputs = validateInputs
        self.telemetryEnabled = telemetryEnabled
        self.telemetryBatchSize = telemetryBatchSize
        self.telemetryFlushInterval = telemetryFlushInterval
        self.otaUpdatesEnabled = otaUpdatesEnabled
        self.serverURL = serverURL
        self.apiKey = apiKey
    }
}

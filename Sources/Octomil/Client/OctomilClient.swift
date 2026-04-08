import Foundation
import CoreML
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Main entry point for the Octomil SDK.
///
/// `OctomilClient` provides a high-level API for:
/// - Device registration
/// - Model download and caching (``models``)
/// - On-device inference
/// - Federated training participation
/// - Device capabilities (``capabilities``)
/// - Custom telemetry (``telemetry``)
/// - Background task scheduling
///
/// # Example Usage
///
/// ```swift
/// let client = OctomilClient(
///     auth: .orgApiKey(apiKey: "<your-api-key>", orgId: "org_123")
/// )
///
/// // Register device
/// let registration = try await client.register()
///
/// // Load model via models namespace
/// let model = try await client.models.load("fraud_detection")
///
/// // Run inference
/// let prediction = try model.predict(input: inputFeatures)
///
/// // Check device capabilities
/// let profile = client.capabilities.current()
///
/// // Track custom event
/// client.telemetry.track(name: "prediction.used", attributes: ["model": "fraud_detection"])
/// ```
public final class OctomilClient: @unchecked Sendable {

    // MARK: - Constants

    /// Default Octomil server host.
    public static let defaultServerHost = "api.octomil.com"

    /// Default Octomil server URL.
    public static let defaultServerURL = URL(string: "https://\(defaultServerHost)")!

    // MARK: - Shared Instance

    /// Shared instance for background operations.
    public private(set) static var shared: OctomilClient?

    // MARK: - Properties

    internal let apiClient: APIClient
    internal let modelManager: ModelManager
    internal let secureStorage: SecureStorage
    internal let configuration: OctomilConfiguration
    internal let logger: Logger

    /// Secure aggregation client, lazily created when SecAgg is used.
    internal var secAggClient: SecureAggregationClient?

    /// Experiments client for A/B testing.
    public private(set) lazy var experiments = ExperimentsClient(
        apiClient: apiClient,
        telemetryQueue: TelemetryQueue.shared
    )

    /// Model lifecycle operations (load, status, unload, list, clearCache).
    public private(set) lazy var models = OctomilModels(
        modelManager: modelManager,
        apiClient: apiClient,
        configuration: configuration,
        deviceIdProvider: { [weak self] in self?.deviceId }
    )

    /// Device capabilities and hardware profile.
    public private(set) lazy var capabilities = CapabilitiesClient()

    /// Public telemetry facade for custom event tracking.
    public private(set) lazy var telemetry = TelemetryClient(
        queueProvider: { TelemetryQueue.shared }
    )

    /// Response API for on-device LLM inference.
    public private(set) lazy var responses = OctomilResponses()

    /// Model catalog service, initialized via ``configure(manifest:)``.
    public internal(set) var catalog: ModelCatalogService?

    /// Readiness manager for managed model downloads.
    public internal(set) var readiness: ModelReadinessManager?

    /// Maps capability to model ID, populated by ``configure(manifest:)``.
    internal var capabilityModelIds: [ModelCapability: String] = [:]

    /// Audio API namespace (transcription, etc.).
    public private(set) lazy var audio = OctomilAudio(runtimeResolver: { [weak self] ref in
        self?.resolveRuntime(ref)
    })

    /// Text prediction API namespace.
    public private(set) lazy var text = OctomilText(runtimeResolver: { [weak self] ref in
        self?.resolveRuntime(ref)
    })

    /// Control-plane sync for configuration, assignments, and rollouts.
    public private(set) lazy var control = ControlSync(apiClient: apiClient)

    /// Offline event queue for offline-first event persistence.
    internal let eventQueue: EventQueue

    /// Organization ID for this client.
    public let orgId: String

    /// Server-assigned device UUID (set after registration).
    internal var serverDeviceId: String?
    /// Client-generated device identifier (e.g., IDFV).
    internal var clientDeviceIdentifier: String?
    internal var deviceRegistration: DeviceRegistrationResponse?

    /// Device identity and auth context, created at configure() time.
    public internal(set) var deviceContext: DeviceContext?

    /// Background task for silent device registration.
    internal var registrationTask: Task<Void, Never>?

    /// Heartbeat timer for automatic health reporting.
    internal var heartbeatTask: Task<Void, Never>?
    internal let heartbeatInterval: TimeInterval

    /// Artifact reconciler for desired-state sync and auto-recovery.
    internal var artifactReconciler: ArtifactReconciler?

    /// Metadata store for installed model artifacts.
    internal var modelMetadataStore: ModelMetadataStore?

    /// Whether the client has been closed via ``close()``.
    public private(set) var isClosed: Bool = false

    // MARK: - Client State

    /// The current client state.
    public private(set) var currentState: ClientState = .uninitialized

    /// Continuation for state stream.
    internal var stateContinuation: AsyncStream<ClientState>.Continuation?

    /// Observable stream of client state transitions.
    public lazy var state: AsyncStream<ClientState> = {
        AsyncStream<ClientState> { continuation in
            self.stateContinuation = continuation
            continuation.yield(self.currentState)
        }
    }()

    // MARK: - Download State

    /// Continuation for download state stream.
    private var downloadStateContinuation: AsyncStream<DownloadState>.Continuation?

    /// Observable stream of model download state transitions.
    public lazy var modelDownloadState: AsyncStream<DownloadState> = {
        AsyncStream<DownloadState> { continuation in
            self.downloadStateContinuation = continuation
            continuation.yield(.idle)
        }
    }()

    /// Whether the device is registered with the server.
    public var isRegistered: Bool {
        return deviceRegistration != nil
    }

    /// The server-assigned device ID (UUID).
    public var deviceId: String? {
        return serverDeviceId ?? deviceRegistration?.id
    }

    /// The client-generated device identifier.
    public var deviceIdentifier: String? {
        return clientDeviceIdentifier ?? deviceRegistration?.deviceIdentifier
    }

    // MARK: - Initialization

    /// Creates a new Octomil client using an ``AuthConfig``.
    ///
    /// This is the sole initializer. Pass either `.orgApiKey(...)` or
    /// `.deviceToken(...)` to configure authentication.
    ///
    /// ```swift
    /// let client = OctomilClient(
    ///     auth: .orgApiKey(apiKey: "edg_...", orgId: "org_123")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - auth: Authentication configuration.
    ///   - configuration: SDK configuration options.
    ///   - heartbeatInterval: Interval for automatic heartbeats (default: 5 minutes).
    public init(
        auth: AuthConfig,
        configuration: OctomilConfiguration = .standard,
        heartbeatInterval: TimeInterval = 300
    ) {
        self.orgId = auth.orgId
        self.configuration = configuration
        self.heartbeatInterval = heartbeatInterval
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "OctomilClient")

        self.secureStorage = SecureStorage()
        self.eventQueue = EventQueue.shared

        // Resolve effective token synchronously: prefer auth.token, fallback to keychain.
        // This avoids fire-and-forget Task{} races where register() could execute
        // before setDeviceToken() completes on the actor-isolated APIClient.
        let authToken = auth.token
        let storedToken = (try? secureStorage.getDeviceToken()) ?? ""
        let effectiveToken = !authToken.isEmpty ? authToken : storedToken

        self.apiClient = APIClient(
            serverURL: auth.serverURL,
            configuration: configuration,
            initialToken: effectiveToken.isEmpty ? nil : effectiveToken
        )

        self.modelManager = ModelManager(
            apiClient: apiClient,
            configuration: configuration
        )

        // Persist effective token to keychain
        if !effectiveToken.isEmpty {
            try? secureStorage.storeDeviceToken(effectiveToken)
        }

        // Try to restore server device ID from keychain
        if let storedId = try? secureStorage.getServerDeviceId() {
            self.serverDeviceId = storedId
        }

        // Apply constructor-provided deviceId from auth config
        if let deviceId = auth.deviceId {
            self.clientDeviceIdentifier = deviceId
            // Forward to telemetry resource context so events carry the device ID
            TelemetryQueue.shared?.setResourceContext(deviceId: deviceId, orgId: auth.orgId)
        }

        // Set as shared instance
        OctomilClient.shared = self
    }

    deinit {
        registrationTask?.cancel()
        heartbeatTask?.cancel()
    }

    // MARK: - Teardown

    /// Tears down the client, releasing all background resources.
    ///
    /// This method:
    /// 1. Stops the heartbeat timer
    /// 2. Flushes any pending telemetry events
    /// 3. Cancels background tasks
    /// 4. Sets ``isClosed`` to `true` and transitions to ``ClientState/closed``
    ///
    /// After calling `close()`, the client should not be reused.
    /// This is the iOS equivalent of `close()` on Android/Python and
    /// `dispose()` on Node.
    public func close() async {
        guard !isClosed else { return }
        isClosed = true

        // Stop background registration
        registrationTask?.cancel()
        registrationTask = nil

        // Stop heartbeat
        heartbeatTask?.cancel()
        heartbeatTask = nil

        // Flush pending telemetry
        await TelemetryQueue.shared?.flush()

        // Transition to closed state
        emitState(.closed)

        // Finish state stream
        stateContinuation?.finish()
        downloadStateContinuation?.finish()

        if configuration.enableLogging {
            logger.info("OctomilClient closed")
        }
    }

    // MARK: - State Helpers

    /// Emits a new client state.
    internal func emitState(_ newState: ClientState) {
        currentState = newState
        stateContinuation?.yield(newState)
    }

    /// Emits a new download state.
    internal func emitDownloadState(_ newState: DownloadState) {
        downloadStateContinuation?.yield(newState)
    }

    // MARK: - Device Info Helpers

    /// Device info collected during registration.
    internal struct LocalDeviceInfo {
        let osVersion: String
        let deviceModel: String
        let totalMemoryMb: Int?
        let availableStorageMb: Int?
        let locale: String?
        let region: String?
        let timezone: String?
        let supportsTraining: Bool
        let coremlVersion: String?
        let hasNeuralEngine: Bool
    }

    internal func buildDeviceInfo() async -> LocalDeviceInfo {
        var availableStorageMb: Int? = nil
        var totalMemoryMb: Int? = nil
        let deviceModel: String
        let osVersion: String

        #if canImport(UIKit)
        // Get storage info
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSize = attrs[.systemFreeSize] as? UInt64 {
            availableStorageMb = Int(freeSize / (1024 * 1024))
        }

        // Get total memory
        totalMemoryMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))

        // Use DeviceMetadata.model for machine identifier (e.g. "iPhone16,1")
        // instead of UIDevice.current.model which returns generic "iPhone"
        deviceModel = DeviceMetadata().model
        osVersion = await MainActor.run { UIDevice.current.systemVersion }
        #else
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        deviceModel = DeviceMetadata().model
        totalMemoryMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        #endif

        // Get locale info
        let currentLocale = Locale.current
        let locale = currentLocale.identifier
        let region: String?
        if #available(iOS 16.0, macOS 13.0, *) {
            region = currentLocale.region?.identifier
        } else {
            region = (currentLocale as NSLocale).countryCode
        }
        let timezone = TimeZone.current.identifier

        return LocalDeviceInfo(
            osVersion: osVersion,
            deviceModel: deviceModel,
            totalMemoryMb: totalMemoryMb,
            availableStorageMb: availableStorageMb,
            locale: locale,
            region: region,
            timezone: timezone,
            supportsTraining: true, // iOS 15+ supports on-device training
            coremlVersion: "5.0",
            hasNeuralEngine: hasNeuralEngine()
        )
    }

    internal func generateDeviceIdentifier() -> String {
        // Use a random UUID persisted in Keychain. NOT IDFV — avoids
        // cross-app tracking and App Store review issues.
        if let storedId = try? secureStorage.getClientDeviceIdentifier() {
            return storedId
        }
        let newId = UUID().uuidString
        try? secureStorage.storeClientDeviceIdentifier(newId)
        return newId
    }

    internal func hasNeuralEngine() -> Bool {
        // Check for Neural Engine availability
        #if canImport(UIKit)
        // A12 Bionic and later have Neural Engine
        // This is a simplified check - in production, use device model mapping
        return true
        #else
        return false
        #endif
    }

    /// Extracts the shape from a CoreML feature description.
    internal func extractShape(from description: MLFeatureDescription) -> [Int] {
        if let constraint = description.multiArrayConstraint {
            return constraint.shape.map { $0.intValue }
        }
        if let imageConstraint = description.imageConstraint {
            return [1, Int(imageConstraint.pixelsHigh), Int(imageConstraint.pixelsWide), 3]
        }
        return []
    }

    /// Returns a string description of a CoreML feature type.
    internal func describeFeatureType(_ type: MLFeatureType) -> String {
        switch type {
        case .invalid:
            return "Invalid"
        case .int64:
            return "Int64"
        case .double:
            return "Double"
        case .string:
            return "String"
        case .multiArray:
            return "MultiArray"
        case .image:
            return "Image"
        case .dictionary:
            return "Dictionary"
        case .sequence:
            return "Sequence"
        @unknown default:
            return "Unknown"
        }
    }

    /// Creates a dummy MLFeatureProvider matching the model's input description.
    internal func createDummyInput(for model: OctomilModel) -> MLFeatureProvider? {
        let inputDescs = model.mlModel.modelDescription.inputDescriptionsByName
        var features: [String: MLFeatureValue] = [:]

        for (name, desc) in inputDescs {
            if let constraint = desc.multiArrayConstraint {
                let shape = constraint.shape
                guard let array = try? MLMultiArray(shape: shape, dataType: .float32) else {
                    return nil
                }
                features[name] = MLFeatureValue(multiArray: array)
            }
        }

        guard !features.isEmpty else { return nil }
        return try? MLDictionaryFeatureProvider(dictionary: features)
    }
}

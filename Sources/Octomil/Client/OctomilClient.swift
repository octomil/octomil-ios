import Foundation
import CoreML
import os.log
#if canImport(UIKit)
import UIKit
#endif

// swiftlint:disable type_body_length
/// Main entry point for the Octomil SDK.
///
/// `OctomilClient` provides a high-level API for:
/// - Device registration
/// - Model download and caching
/// - On-device inference
/// - Federated training participation
/// - Background task scheduling
///
/// # Example Usage
///
/// ```swift
/// let client = OctomilClient(
///     deviceAccessToken: "<short-lived-device-token>",
///     orgId: "org_123",
///     serverURL: URL(string: "https://api.octomil.com")!
/// )
///
/// // Register device
/// let registration = try await client.register()
///
/// // Download model
/// let model = try await client.downloadModel(modelId: "fraud_detection")
///
/// // Run inference
/// let prediction = try model.predict(input: inputFeatures)
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

    private let apiClient: APIClient
    private let modelManager: ModelManager
    private let secureStorage: SecureStorage
    private let configuration: OctomilConfiguration
    private let logger: Logger

    /// Secure aggregation client, lazily created when SecAgg is used.
    private var secAggClient: SecureAggregationClient?

    /// Experiments client for A/B testing.
    public private(set) lazy var experiments = ExperimentsClient(
        apiClient: apiClient,
        telemetryQueue: TelemetryQueue.shared
    )

    /// Offline event queue for offline-first event persistence.
    private let eventQueue: EventQueue

    /// Organization ID for this client.
    public let orgId: String

    /// Server-assigned device UUID (set after registration).
    private var serverDeviceId: String?
    /// Client-generated device identifier (e.g., IDFV).
    private var clientDeviceIdentifier: String?
    private var deviceRegistration: DeviceRegistrationResponse?

    /// Heartbeat timer for automatic health reporting.
    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval

    /// Whether the client has been closed via ``close()``.
    public private(set) var isClosed: Bool = false

    // MARK: - Client State

    /// The current client state.
    public private(set) var currentState: ClientState = .uninitialized

    /// Continuation for state stream.
    private var stateContinuation: AsyncStream<ClientState>.Continuation?

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

    /// Creates a new Octomil client.
    /// - Parameters:
    ///   - deviceAccessToken: Short-lived device access token from backend bootstrap flow.
    ///   - orgId: Organization identifier.
    ///   - serverURL: Base URL of the Octomil server.
    ///   - configuration: SDK configuration options.
    ///   - heartbeatInterval: Interval for automatic heartbeats (default: 5 minutes).
    public init(
        deviceAccessToken: String,
        orgId: String,
        serverURL: URL = OctomilClient.defaultServerURL,
        configuration: OctomilConfiguration = .standard,
        heartbeatInterval: TimeInterval = 300
    ) {
        self.orgId = orgId
        self.configuration = configuration
        self.heartbeatInterval = heartbeatInterval
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "OctomilClient")

        self.secureStorage = SecureStorage()
        self.eventQueue = EventQueue.shared
        self.apiClient = APIClient(
            serverURL: serverURL,
            configuration: configuration
        )

        self.modelManager = ModelManager(
            apiClient: apiClient,
            configuration: configuration
        )

        // Store device token securely
        try? secureStorage.storeDeviceToken(deviceAccessToken)
        Task {
            await apiClient.setDeviceToken(deviceAccessToken)
        }

        // Try to restore device token from keychain
        if let storedToken = try? secureStorage.getDeviceToken() {
            Task {
                await apiClient.setDeviceToken(storedToken)
            }
        }

        // Try to restore server device ID from keychain
        if let storedId = try? secureStorage.getServerDeviceId() {
            self.serverDeviceId = storedId
        }

        // Set as shared instance
        OctomilClient.shared = self
    }

    deinit {
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

    // MARK: - Device Registration

    /// Registers this device with the Octomil server.
    ///
    /// Registration establishes this device's identity and enables
    /// participation in federated learning rounds.
    ///
    /// - Parameters:
    ///   - deviceIdentifier: Client-generated device ID (e.g., IDFV). If nil, auto-generated.
    ///   - appVersion: Host application version.
    ///   - metadata: Optional additional metadata.
    /// - Returns: Registration information including server-assigned ID.
    /// - Throws: `OctomilError` if registration fails.
    public func register(
        deviceIdentifier: String? = nil,
        appVersion: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> DeviceRegistrationResponse {
        emitState(.initializing)

        if configuration.enableLogging {
            logger.info("Registering device...")
        }

        // Generate or use provided device identifier
        let identifier = deviceIdentifier ?? generateDeviceIdentifier()
        self.clientDeviceIdentifier = identifier

        let deviceInfo = await buildDeviceInfo()

        let capabilities = DeviceCapabilities(
            supportsTraining: deviceInfo.supportsTraining,
            coremlVersion: deviceInfo.coremlVersion,
            hasNeuralEngine: deviceInfo.hasNeuralEngine,
            maxBatchSize: 32,
            supportedFormats: ["coreml", "onnx"]
        )

        let hardwareInfo = DeviceInfoRequest(
            manufacturer: "Apple",
            model: deviceInfo.deviceModel,
            cpuArchitecture: "arm64",
            gpuAvailable: deviceInfo.hasNeuralEngine,
            totalMemoryMb: deviceInfo.totalMemoryMb,
            availableStorageMb: deviceInfo.availableStorageMb
        )

        let request = DeviceRegistrationRequest(
            deviceIdentifier: identifier,
            orgId: orgId,
            platform: "ios",
            osVersion: deviceInfo.osVersion,
            sdkVersion: OctomilVersion.current,
            appVersion: appVersion,
            deviceInfo: hardwareInfo,
            locale: deviceInfo.locale,
            region: deviceInfo.region,
            timezone: deviceInfo.timezone,
            metadata: metadata,
            capabilities: capabilities
        )

        let registration = try await apiClient.registerDevice(request)

        // Store registration info
        self.serverDeviceId = registration.id
        self.deviceRegistration = registration

        // Store server device ID securely for persistence
        try? secureStorage.storeServerDeviceId(registration.id)

        // Start automatic heartbeat
        startHeartbeat()

        emitState(.ready)

        if configuration.enableLogging {
            logger.info("Device registered with ID: \(registration.id)")
        }

        return registration
    }

    // MARK: - Heartbeat

    /// Sends a heartbeat to the server.
    ///
    /// - Parameter availableStorageMb: Current available storage (optional).
    /// - Returns: Heartbeat response.
    /// - Throws: `OctomilError` if heartbeat fails.
    @discardableResult
    public func sendHeartbeat(availableStorageMb: Int? = nil) async throws -> HeartbeatResponse {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        var metadata: [String: String]? = nil
        if let availableStorageMb = availableStorageMb {
            metadata = ["available_storage_mb": String(availableStorageMb)]
        }

        let request = HeartbeatRequest(metadata: metadata)

        return try await apiClient.sendHeartbeat(deviceId: deviceId, request: request)
    }

    /// Starts automatic heartbeat reporting.
    public func startHeartbeat() {
        heartbeatTask?.cancel()

        heartbeatTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                    _ = try await self.sendHeartbeat()
                    if self.configuration.enableLogging {
                        self.logger.debug("Heartbeat sent successfully")
                    }
                } catch {
                    if self.configuration.enableLogging {
                        self.logger.warning("Heartbeat failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Stops automatic heartbeat reporting.
    public func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        emitState(.closed)
    }

    // MARK: - Device Groups

    /// Gets the groups this device belongs to.
    ///
    /// - Returns: List of device groups.
    /// - Throws: `OctomilError` if the request fails.
    public func getGroups() async throws -> [DeviceGroup] {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        return try await apiClient.getDeviceGroups(deviceId: deviceId)
    }

    /// Checks if this device belongs to a specific group.
    ///
    /// - Parameter groupId: The group ID to check.
    /// - Returns: True if device is a member of the group.
    /// - Throws: `OctomilError` if the request fails.
    public func isMemberOf(groupId: String) async throws -> Bool {
        let groups = try await getGroups()
        return groups.contains { $0.id == groupId }
    }

    /// Checks if this device belongs to a group with the given name.
    ///
    /// - Parameter groupName: The group name to check.
    /// - Returns: True if device is a member of a group with that name.
    /// - Throws: `OctomilError` if the request fails.
    public func isMemberOf(groupName: String) async throws -> Bool {
        let groups = try await getGroups()
        return groups.contains { $0.name == groupName }
    }

    /// Gets this device's full information from the server.
    ///
    /// - Returns: Full device information.
    /// - Throws: `OctomilError` if the request fails.
    public func getDeviceInfo() async throws -> DeviceInfo {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        return try await apiClient.getDeviceInfo(deviceId: deviceId)
    }

    // MARK: - Model Management

    /// Downloads a model from the server.
    ///
    /// The model is cached locally after download for offline use.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to download.
    ///   - version: Optional specific version. If nil, downloads the latest version.
    /// - Returns: The downloaded model ready for inference.
    /// - Throws: `OctomilError` if download fails.
    public func downloadModel(
        modelId: String,
        version: String? = nil
    ) async throws -> OctomilModel {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Downloading model: \(modelId)")
        }

        // Resolve version if not specified
        let resolvedVersion: String
        if let version = version {
            resolvedVersion = version
        } else {
            let resolution = try await apiClient.resolveVersion(deviceId: deviceId, modelId: modelId)
            resolvedVersion = resolution.version
        }

        return try await modelManager.downloadModel(modelId: modelId, version: resolvedVersion)
    }

    /// Gets a cached model without network access.
    ///
    /// - Parameter modelId: Identifier of the model.
    /// - Returns: The cached model, or nil if not cached.
    public func getCachedModel(modelId: String) -> OctomilModel? {
        return modelManager.getCachedModel(modelId: modelId)
    }

    /// Gets a cached model with a specific version.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model.
    ///   - version: Version of the model.
    /// - Returns: The cached model, or nil if not cached.
    public func getCachedModel(modelId: String, version: String) -> OctomilModel? {
        return modelManager.getCachedModel(modelId: modelId, version: version)
    }

    /// Checks if a model update is available.
    ///
    /// - Parameter modelId: Identifier of the model.
    /// - Returns: Update information if available, nil otherwise.
    /// - Throws: `OctomilError` if the check fails.
    public func checkForUpdates(modelId: String) async throws -> ModelUpdateInfo? {
        guard let cachedModel = getCachedModel(modelId: modelId) else {
            return nil
        }

        return try await apiClient.checkForUpdates(
            modelId: modelId,
            currentVersion: cachedModel.version
        )
    }

    /// Clears all cached models.
    public func clearCache() async throws {
        try await modelManager.clearCache()

        if configuration.enableLogging {
            logger.info("Model cache cleared")
        }
    }

    // MARK: - Streaming Inference

    /// Streams generative inference and auto-reports metrics to the server.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - input: Modality-specific input.
    ///   - modality: The output modality.
    ///   - engine: Optional custom engine. Defaults to a modality-appropriate engine.
    /// - Returns: An ``AsyncThrowingStream`` of ``InferenceChunk``.
    public func predictStream(
        model: OctomilModel,
        input: Any,
        modality: Modality,
        engine: StreamingInferenceEngine? = nil
    ) -> AsyncThrowingStream<InferenceChunk, Error> {
        let (stream, getResult) = model.predictStream(input: input, modality: modality, engine: engine)
        let apiClient = self.apiClient
        let deviceId = self.deviceId
        let orgId = self.orgId
        let sessionId = UUID().uuidString

        // Report generation_started via v2 OTLP
        if let deviceId = deviceId {
            Task {
                let resource = TelemetryResource(deviceId: deviceId, orgId: orgId)
                let event = TelemetryEvent(
                    name: "inference.generation_started",
                    attributes: [
                        "model.id": .string(model.id),
                        "model.version": .string(model.version),
                        "inference.modality": .string(modality.rawValue),
                        "inference.session_id": .string(sessionId),
                        "model.format": .string("coreml"),
                    ]
                )
                let envelope = TelemetryEnvelope(resource: resource, events: [event])
                try? await apiClient.reportTelemetryEvents(envelope)
            }
        }

        // Wrap the stream to report completion via v2 OTLP
        return AsyncThrowingStream<InferenceChunk, Error> { continuation in
            let task = Task {
                var failed = false
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                } catch {
                    failed = true
                    continuation.finish(throwing: error)
                }

                if !failed {
                    continuation.finish()
                }

                // Report completion event via v2 OTLP
                if let deviceId = deviceId, let result = getResult() {
                    let eventName = failed ? "inference.generation_failed" : "inference.generation_completed"
                    var attrs: [String: TelemetryValue] = [
                        "model.id": .string(model.id),
                        "model.version": .string(model.version),
                        "inference.modality": .string(modality.rawValue),
                        "inference.session_id": .string(sessionId),
                        "inference.ttft_ms": .double(result.ttfcMs),
                        "inference.duration_ms": .double(result.totalDurationMs),
                        "inference.total_chunks": .int(result.totalChunks),
                        "inference.throughput": .double(result.throughput),
                        "model.format": .string("coreml"),
                    ]
                    if failed {
                        attrs["inference.success"] = .bool(false)
                    }
                    let resource = TelemetryResource(deviceId: deviceId, orgId: orgId)
                    let event = TelemetryEvent(name: eventName, attributes: attrs)
                    let envelope = TelemetryEnvelope(resource: resource, events: [event])
                    try? await apiClient.reportTelemetryEvents(envelope)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Unified Training

    /// Train the model on local data with a single, unified API.
    ///
    /// This is the **recommended** way to do all training. It replaces the
    /// previous split between ``joinRound`` and ``trainLocal``.
    ///
    /// ## Upload behavior
    ///
    /// The `uploadPolicy` parameter controls what happens after training:
    /// - ``UploadPolicy/auto``: Extracts weights and uploads automatically.
    ///   Uses SecAgg if enabled and a `roundId` is provided.
    /// - ``UploadPolicy/manual``: Extracts weights but does NOT upload.
    ///   Returns them in ``TrainingOutcome/weightUpdate`` for you to handle.
    /// - ``UploadPolicy/disabled``: No weight extraction or upload. Pure local training.
    ///
    /// ## Degraded mode
    ///
    /// If the model lacks CoreML updatable parameters, behavior depends on
    /// ``OctomilConfiguration/allowDegradedTraining``:
    /// - **false (default)**: Throws ``MissingTrainingSignatureError``.
    /// - **true**: Runs forward-pass training (no weight updates) and sets
    ///   ``TrainingOutcome/degraded`` to `true`.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - trainingConfig: Training configuration.
    ///   - uploadPolicy: Controls weight extraction and upload.
    ///   - roundId: Optional federated learning round ID.
    /// - Returns: ``TrainingOutcome`` with training metrics, optional weights, and upload status.
    /// - Throws: ``MissingTrainingSignatureError`` if model lacks training support and degraded mode is disabled.
    public func train(
        model: OctomilModel,
        dataProvider: @escaping () -> MLBatchProvider,
        trainingConfig: TrainingConfig = .standard,
        uploadPolicy: UploadPolicy = .auto,
        roundId: String? = nil
    ) async throws -> TrainingOutcome {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        // Check for training signature support
        let isDegraded = !model.supportsTraining
        if isDegraded && !configuration.allowDegradedTraining {
            throw MissingTrainingSignatureError(
                availableSignatures: Array(model.inputDescriptions.keys)
            )
        }

        if isDegraded, configuration.enableLogging {
            logger.error("MODEL TRAINING DEGRADED: Model lacks updatable parameters. Weights will NOT be updated on-device.")
        }

        if configuration.enableLogging {
            logger.info("Starting training: policy=\(uploadPolicy.rawValue), round=\(roundId ?? "none"), degraded=\(isDegraded)")
        }

        // Record training started telemetry
        TelemetryQueue.shared?.reportTrainingStarted(
            modelId: model.id,
            version: model.version,
            roundId: roundId ?? "local",
            numSamples: 0
        )
        let trainingStart = CFAbsoluteTimeGetCurrent()

        // Train locally
        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult: TrainingResult

        do {
            if isDegraded {
                // Degraded mode: run inference on training data to collect metrics
                let data = dataProvider()
                let startTime = Date()
                // Run a single prediction to measure forward-pass metrics
                if data.count > 0 {
                    let firstFeature = data.features(at: 0)
                    _ = try? model.predict(input: firstFeature)
                }
                let trainingTime = Date().timeIntervalSince(startTime)
                trainingResult = TrainingResult(
                    sampleCount: data.count,
                    loss: nil,
                    accuracy: nil,
                    trainingTime: trainingTime,
                    metrics: ["training_method": 0.0, "degraded": 1.0]
                )
            } else {
                trainingResult = try await trainer.train(
                    model: model,
                    dataProvider: dataProvider,
                    config: trainingConfig
                )
            }
        } catch {
            // Record training failed telemetry
            let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Handle weight extraction and upload based on policy
        var weightUpdate: WeightUpdate? = nil
        var uploaded = false
        var usedSecAgg = false

        do {
            switch uploadPolicy {
            case .auto:
                if !isDegraded {
                    weightUpdate = try await trainer.extractWeightUpdate(
                        model: model,
                        trainingResult: trainingResult
                    )
                    var update = weightUpdate!
                    update = WeightUpdate(
                        modelId: update.modelId,
                        version: update.version,
                        deviceId: deviceId,
                        weightsData: update.weightsData,
                        sampleCount: update.sampleCount,
                        metrics: update.metrics,
                        dpMetadata: update.dpMetadata
                    )
                    weightUpdate = update

                    // Use SecAgg if available and round-based
                    if let roundId = roundId, secAggClient != nil {
                        usedSecAgg = true
                        try await uploadWithSecAgg(
                            weightUpdate: update,
                            roundId: roundId,
                            deviceId: deviceId
                        )
                        uploaded = true
                    } else {
                        try await apiClient.uploadWeights(update)
                        uploaded = true
                    }
                }

            case .manual:
                if !isDegraded {
                    weightUpdate = try await trainer.extractWeightUpdate(
                        model: model,
                        trainingResult: trainingResult
                    )
                }

            case .disabled:
                break
            }
        } catch {
            // Record training failed telemetry (upload phase)
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Record training completed telemetry
        let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
        TelemetryQueue.shared?.reportTrainingCompleted(
            modelId: model.id,
            version: model.version,
            durationMs: trainingDurationMs,
            loss: trainingResult.loss ?? 0.0,
            accuracy: trainingResult.accuracy ?? 0.0
        )

        // Record weight upload telemetry if weights were uploaded
        if uploaded, let weightUpdate = weightUpdate {
            TelemetryQueue.shared?.reportWeightUpload(
                modelId: model.id,
                roundId: roundId ?? "local",
                sampleCount: weightUpdate.sampleCount
            )
        }

        let outcome = TrainingOutcome(
            trainingResult: trainingResult,
            weightUpdate: weightUpdate,
            uploaded: uploaded,
            secureAggregation: usedSecAgg,
            uploadPolicy: uploadPolicy,
            degraded: isDegraded
        )

        if configuration.enableLogging {
            logger.info("Training complete: \(trainingResult.sampleCount) samples, policy=\(uploadPolicy.rawValue), uploaded=\(uploaded), degraded=\(isDegraded)")
        }

        return outcome
    }

    /// Uploads weight updates using secure aggregation.
    private func uploadWithSecAgg(
        weightUpdate: WeightUpdate,
        roundId: String,
        deviceId: String
    ) async throws {
        if secAggClient == nil {
            secAggClient = SecureAggregationClient()
        }
        let secAgg = secAggClient!

        let session = try await apiClient.joinSecAggSession(deviceId: deviceId, roundId: roundId)

        let secAggConfig = SecAggConfiguration(
            threshold: session.threshold,
            totalClients: session.totalClients,
            privacyBudget: session.privacyBudget,
            keyLength: session.keyLength
        )

        await secAgg.beginSession(
            sessionId: session.sessionId,
            clientIndex: session.clientIndex,
            configuration: secAggConfig
        )

        let sharesData = try await secAgg.generateKeyShares()
        let shareKeysRequest = SecAggShareKeysRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            sharesData: sharesData.base64EncodedString()
        )
        try await apiClient.submitSecAggShares(shareKeysRequest)

        let maskedWeights = try await secAgg.maskModelUpdate(weightUpdate.weightsData)
        let maskedInputRequest = SecAggMaskedInputRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            maskedWeightsData: maskedWeights.base64EncodedString(),
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics
        )
        try await apiClient.submitSecAggMaskedInput(maskedInputRequest)

        let unmaskInfo = try await apiClient.getSecAggUnmaskInfo(
            sessionId: session.sessionId,
            deviceId: deviceId
        )

        if unmaskInfo.unmaskingRequired {
            let unmaskData = try await secAgg.provideUnmaskingShares(
                droppedClientIndices: unmaskInfo.droppedClientIndices
            )
            let unmaskRequest = SecAggUnmaskRequest(
                sessionId: session.sessionId,
                deviceId: deviceId,
                unmaskData: unmaskData.base64EncodedString()
            )
            try await apiClient.submitSecAggUnmask(unmaskRequest)
        }

        await secAgg.reset()
    }

    // MARK: - Model Contract & Info

    /// Returns the model's input/output contract for validation.
    ///
    /// Use this at setup time to validate that your data pipeline produces
    /// the correct shapes and types before calling inference or training.
    ///
    /// - Parameter model: The model to inspect.
    /// - Returns: A ``ModelContract`` describing the model, or nil if tensor info is unavailable.
    public func getModelContract(for model: OctomilModel) -> ModelContract? {
        guard let tensorInfo = getTensorInfo(for: model) else {
            return nil
        }
        return ModelContract(
            modelId: model.id,
            version: model.version,
            inputShape: tensorInfo.inputShape,
            outputShape: tensorInfo.outputShape,
            inputType: tensorInfo.inputType,
            outputType: tensorInfo.outputType,
            hasTrainingSignature: model.supportsTraining,
            signatureKeys: model.supportsTraining ? ["train", "infer"] : ["infer"]
        )
    }

    /// Returns summary information about a loaded model.
    ///
    /// - Parameter model: The model to inspect.
    /// - Returns: A ``ModelInfo`` describing the model.
    public func getModelInfo(for model: OctomilModel) -> ModelInfo {
        let tensorInfo = getTensorInfo(for: model)
        return ModelInfo(
            modelId: model.id,
            version: model.version,
            format: model.metadata.format,
            sizeBytes: Int64(model.metadata.fileSize),
            inputShape: tensorInfo?.inputShape ?? [],
            outputShape: tensorInfo?.outputShape ?? [],
            usingNeuralEngine: hasNeuralEngine()
        )
    }

    /// Returns tensor shape/type information for a loaded model.
    ///
    /// - Parameter model: The model to inspect.
    /// - Returns: A ``TensorInfo`` with input/output shapes and types, or nil if unavailable.
    public func getTensorInfo(for model: OctomilModel) -> TensorInfo? {
        let inputDescs = model.mlModel.modelDescription.inputDescriptionsByName
        let outputDescs = model.mlModel.modelDescription.outputDescriptionsByName

        guard let firstInput = inputDescs.values.first,
              let firstOutput = outputDescs.values.first else {
            return nil
        }

        let inputShape = extractShape(from: firstInput)
        let outputShape = extractShape(from: firstOutput)
        let inputType = describeFeatureType(firstInput.type)
        let outputType = describeFeatureType(firstOutput.type)

        return TensorInfo(
            inputShape: inputShape,
            outputShape: outputShape,
            inputType: inputType,
            outputType: outputType
        )
    }

    // MARK: - Warmup

    /// Runs warmup inference to absorb cold-start costs before real inference.
    ///
    /// Performs a cold inference pass followed by a warm pass, then compares
    /// Neural Engine vs CPU to determine the best compute path.
    ///
    /// - Parameter model: The model to warm up.
    /// - Returns: A ``WarmupResult`` with timing information, or nil if warmup fails.
    public func warmup(model: OctomilModel) async -> WarmupResult? {
        guard let firstInput = model.mlModel.modelDescription.inputDescriptionsByName.values.first else {
            return nil
        }

        // Create a dummy input matching the model's expected shape
        guard let dummyInput = createDummyInput(for: model) else {
            return nil
        }

        // Cold inference
        let coldStart = Date()
        _ = try? model.predict(input: dummyInput)
        let coldInferenceMs = Date().timeIntervalSince(coldStart) * 1000

        // Warm inference
        let warmStart = Date()
        _ = try? model.predict(input: dummyInput)
        let warmInferenceMs = Date().timeIntervalSince(warmStart) * 1000

        // CPU-only inference for comparison (use CPU-only compute units)
        var cpuInferenceMs: Double? = nil
        let cpuConfig = MLModelConfiguration()
        cpuConfig.computeUnits = .cpuOnly
        if let cpuModel = try? MLModel(contentsOf: model.compiledModelURL, configuration: cpuConfig) {
            let cpuStart = Date()
            _ = try? await cpuModel.prediction(from: dummyInput)
            cpuInferenceMs = Date().timeIntervalSince(cpuStart) * 1000
        }

        let usingNE = hasNeuralEngine()
        var activeDelegate = usingNE ? "neural_engine" : "cpu"
        var disabledDelegates: [String] = []

        // If CPU is faster than Neural Engine, disable NE
        if let cpuMs = cpuInferenceMs, cpuMs < warmInferenceMs, usingNE {
            activeDelegate = "cpu"
            disabledDelegates.append("neural_engine")
        }

        let result = WarmupResult(
            coldInferenceMs: coldInferenceMs,
            warmInferenceMs: warmInferenceMs,
            cpuInferenceMs: cpuInferenceMs,
            usingNeuralEngine: activeDelegate == "neural_engine",
            activeDelegate: activeDelegate,
            disabledDelegates: disabledDelegates
        )

        // Report warmup event
        if let deviceId = self.deviceId {
            Task {
                try? await apiClient.trackMetric(
                    experimentId: model.id,
                    event: TrackingEvent(
                        name: "MODEL_WARMUP_COMPLETED",
                        properties: [
                            "cold_inference_ms": String(format: "%.2f", coldInferenceMs),
                            "warm_inference_ms": String(format: "%.2f", warmInferenceMs),
                            "using_neural_engine": String(result.usingNeuralEngine),
                            "active_delegate": result.activeDelegate,
                            "delegate_disabled": String(result.delegateDisabled),
                            "disabled_delegates": result.disabledDelegates.joined(separator: ",")
                        ]
                    )
                )
            }
        }

        if configuration.enableLogging {
            let coldStr = String(format: "%.1f", coldInferenceMs)
            let warmStr = String(format: "%.1f", warmInferenceMs)
            logger.info("Warmup complete: cold=\(coldStr)ms, warm=\(warmStr)ms, delegate=\(activeDelegate)")
        }

        return result
    }

    // MARK: - Legacy Training

    /// Participates in a federated training round.
    ///
    /// This method:
    /// 1. Downloads the latest model if needed
    /// 2. Trains the model on local data
    /// 3. Extracts weight updates
    /// 4. Uploads updates to the server
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Result of the training round.
    /// - Throws: `OctomilError` if training fails.
    public func joinRound(
        modelId: String,
        dataProvider: @escaping () -> MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Joining training round for model: \(modelId)")
        }

        // Get or download model
        let model: OctomilModel
        if let cached = getCachedModel(modelId: modelId) {
            // Check for updates
            if let updateInfo = try? await checkForUpdates(modelId: modelId), updateInfo.isRequired {
                model = try await downloadModel(modelId: modelId, version: updateInfo.newVersion)
            } else {
                model = cached
            }
        } else {
            model = try await downloadModel(modelId: modelId)
        }

        // Record training started telemetry
        let participateRoundId = UUID().uuidString
        TelemetryQueue.shared?.reportTrainingStarted(
            modelId: model.id,
            version: model.version,
            roundId: participateRoundId,
            numSamples: 0
        )
        let trainingStart = CFAbsoluteTimeGetCurrent()

        // Train locally
        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult: TrainingResult
        do {
            trainingResult = try await trainer.train(
                model: model,
                dataProvider: dataProvider,
                config: config
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Extract and upload weights
        do {
            var weightUpdate = try await trainer.extractWeightUpdate(
                model: model,
                trainingResult: trainingResult
            )
            weightUpdate = WeightUpdate(
                modelId: weightUpdate.modelId,
                version: weightUpdate.version,
                deviceId: deviceId,
                weightsData: weightUpdate.weightsData,
                sampleCount: weightUpdate.sampleCount,
                metrics: weightUpdate.metrics
            )

            try await apiClient.uploadWeights(weightUpdate)

            // Record weight upload telemetry
            TelemetryQueue.shared?.reportWeightUpload(
                modelId: model.id,
                roundId: participateRoundId,
                sampleCount: weightUpdate.sampleCount
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Record training completed telemetry
        let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
        TelemetryQueue.shared?.reportTrainingCompleted(
            modelId: model.id,
            version: model.version,
            durationMs: trainingDurationMs,
            loss: trainingResult.loss ?? 0.0,
            accuracy: trainingResult.accuracy ?? 0.0
        )

        let roundResult = RoundResult(
            roundId: participateRoundId,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            logger.info("Training round completed: \(trainingResult.sampleCount) samples")
        }

        return roundResult
    }

    /// Participates in a federated training round with secure aggregation.
    ///
    /// The client never sends raw gradients to the server. Instead:
    /// 1. Joins a SecAgg session for the round
    /// 2. Generates and distributes Shamir secret shares of a mask seed
    /// 3. Trains locally and masks the weight update before uploading
    /// 4. Participates in unmasking so the server can reconstruct the aggregate
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - roundId: Server-assigned round identifier.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Result of the training round.
    /// - Throws: `OctomilError` if training or SecAgg protocol fails.
    public func joinSecureRound(
        modelId: String,
        roundId: String,
        dataProvider: @escaping () -> MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Joining SecAgg round \(roundId) for model \(modelId)")
        }

        // Lazily create SecAgg client
        if secAggClient == nil {
            secAggClient = SecureAggregationClient()
        }
        let secAgg = secAggClient!

        // Phase 0: Join the SecAgg session
        let session = try await apiClient.joinSecAggSession(deviceId: deviceId, roundId: roundId)

        let secAggConfig = SecAggConfiguration(
            threshold: session.threshold,
            totalClients: session.totalClients,
            privacyBudget: session.privacyBudget,
            keyLength: session.keyLength
        )

        await secAgg.beginSession(
            sessionId: session.sessionId,
            clientIndex: session.clientIndex,
            configuration: secAggConfig
        )

        // Phase 1: Generate and submit key shares
        let sharesData = try await secAgg.generateKeyShares()
        let shareKeysRequest = SecAggShareKeysRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            sharesData: sharesData.base64EncodedString()
        )
        try await apiClient.submitSecAggShares(shareKeysRequest)

        // Train locally (same as non-SecAgg path)
        let model: OctomilModel
        if let cached = getCachedModel(modelId: modelId) {
            model = cached
        } else {
            model = try await downloadModel(modelId: modelId)
        }

        // Record training started telemetry
        TelemetryQueue.shared?.reportTrainingStarted(
            modelId: modelId,
            version: model.version,
            roundId: roundId,
            numSamples: 0
        )
        let trainingStart = CFAbsoluteTimeGetCurrent()

        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult: TrainingResult
        do {
            trainingResult = try await trainer.train(
                model: model,
                dataProvider: dataProvider,
                config: config
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: modelId,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        let weightUpdate: WeightUpdate
        do {
            weightUpdate = try await trainer.extractWeightUpdate(
                model: model,
                trainingResult: trainingResult
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: modelId,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Phase 2: Mask and submit the model update
        let maskedWeights = try await secAgg.maskModelUpdate(weightUpdate.weightsData)

        let maskedInputRequest = SecAggMaskedInputRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            maskedWeightsData: maskedWeights.base64EncodedString(),
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics
        )
        try await apiClient.submitSecAggMaskedInput(maskedInputRequest)

        // Record weight upload telemetry
        TelemetryQueue.shared?.reportWeightUpload(
            modelId: modelId,
            roundId: roundId,
            sampleCount: weightUpdate.sampleCount
        )

        // Phase 3: Unmasking
        let unmaskInfo = try await apiClient.getSecAggUnmaskInfo(
            sessionId: session.sessionId,
            deviceId: deviceId
        )

        if unmaskInfo.unmaskingRequired {
            let unmaskData = try await secAgg.provideUnmaskingShares(
                droppedClientIndices: unmaskInfo.droppedClientIndices
            )
            let unmaskRequest = SecAggUnmaskRequest(
                sessionId: session.sessionId,
                deviceId: deviceId,
                unmaskData: unmaskData.base64EncodedString()
            )
            try await apiClient.submitSecAggUnmask(unmaskRequest)
        }

        await secAgg.reset()

        // Record training completed telemetry
        let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
        TelemetryQueue.shared?.reportTrainingCompleted(
            modelId: modelId,
            version: model.version,
            durationMs: trainingDurationMs,
            loss: trainingResult.loss ?? 0.0,
            accuracy: trainingResult.accuracy ?? 0.0
        )

        let roundResult = RoundResult(
            roundId: roundId,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            logger.info("SecAgg round \(roundId) completed: \(trainingResult.sampleCount) samples")
        }

        return roundResult
    }

    /// Trains a model locally without uploading weights.
    ///
    /// Useful for testing and validation.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - data: Training data provider.
    ///   - config: Training configuration.
    /// - Returns: Training result.
    /// - Throws: `OctomilError` if training fails.
    public func trainLocal(
        model: OctomilModel,
        data: MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> TrainingResult {
        let trainer = FederatedTrainer(configuration: configuration)
        return try await trainer.train(
            model: model,
            dataProvider: { data },
            config: config
        )
    }

    // MARK: - Background Operations

    /// Enables background training when conditions are met.
    ///
    /// Background training runs during device idle time when:
    /// - Device is connected to power (optional)
    /// - Network is available
    /// - Battery level is sufficient
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - constraints: Background execution constraints.
    #if os(iOS)
    public func enableBackgroundTraining(
        modelId: String,
        dataProvider: @escaping @Sendable () -> MLBatchProvider,
        constraints: BackgroundConstraints = .standard
    ) {
        let sync = BackgroundSync.shared
        sync.configure(
            modelId: modelId,
            dataProvider: dataProvider,
            constraints: constraints,
            client: self
        )
        sync.scheduleNextTraining()

        if configuration.enableLogging {
            logger.info("Background training enabled for model: \(modelId)")
        }
    }

    /// Disables background training.
    public func disableBackgroundTraining() {
        BackgroundSync.shared.cancelScheduledTraining()

        if configuration.enableLogging {
            logger.info("Background training disabled")
        }
    }
    #endif

    // MARK: - Federated Analytics

    /// Creates a federated analytics client for the given federation.
    ///
    /// - Parameter federationId: The federation to run analytics against.
    /// - Returns: A ``FederatedAnalyticsClient`` bound to this client's API connection.
    public func analytics(federationId: String) -> FederatedAnalyticsClient {
        return FederatedAnalyticsClient(apiClient: apiClient, federationId: federationId)
    }

    // MARK: - Metric Tracking

    /// Tracks a metric for an experiment.
    ///
    /// Metrics are persisted to the local event queue first (offline-first),
    /// then forwarded to the server.
    ///
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - eventName: Name of the event.
    ///   - properties: Event properties.
    public func trackMetric(
        experimentId: String,
        eventName: String,
        properties: [String: String] = [:]
    ) async throws {
        let event = TrackingEvent(
            name: eventName,
            properties: properties,
            timestamp: Date()
        )

        // Persist to local queue first (offline-first)
        await eventQueue.addTrainingEvent(
            type: eventName,
            metadata: properties
        )

        // Report experiment metric if properties contain metric_name and metric_value
        if let metricName = properties["metric_name"],
           let metricValueStr = properties["metric_value"],
           let metricValue = Double(metricValueStr) {
            TelemetryQueue.shared?.reportExperimentMetric(
                experimentId: experimentId,
                metricName: metricName,
                metricValue: metricValue
            )
        }

        try await apiClient.trackMetric(experimentId: experimentId, event: event)
    }

    // MARK: - Round Management

    /// Checks if this device has been selected for an active training round.
    ///
    /// Polls the server for rounds in the "waiting_for_updates" state for the
    /// given model. Returns the first matching round assignment, or nil
    /// if no round is currently active for this device.
    ///
    /// - Parameter modelId: The model to check for round assignments.
    /// - Returns: The round assignment, or nil if none available.
    /// - Throws: `OctomilError` if the request fails.
    public func checkForRoundAssignment(modelId: String) async throws -> RoundAssignment? {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        let rounds = try await apiClient.listRounds(
            modelId: modelId,
            state: "waiting_for_updates",
            deviceId: deviceId
        )

        return rounds.first
    }

    /// Gets the current status of a training round.
    ///
    /// - Parameter roundId: The round to query.
    /// - Returns: The round details.
    /// - Throws: `OctomilError` if the request fails.
    public func getRoundStatus(roundId: String) async throws -> RoundAssignment {
        return try await apiClient.getRound(roundId: roundId)
    }

    // MARK: - Direct Inference

    /// Runs inference on a model with raw input data.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - input: Input feature provider.
    /// - Returns: Model prediction output.
    /// - Throws: Error if inference fails.
    public func runInference(
        model: OctomilModel,
        input: MLFeatureProvider
    ) throws -> MLFeatureProvider {
        return try model.predict(input: input)
    }

    /// Classifies input and returns top-K predictions sorted by confidence.
    ///
    /// - Parameters:
    ///   - model: The model to classify with.
    ///   - input: Input feature provider.
    ///   - topK: Number of top predictions to return (default: 5).
    /// - Returns: Array of (feature name, confidence) pairs.
    /// - Throws: Error if inference fails.
    public func classify(
        model: OctomilModel,
        input: MLFeatureProvider,
        topK: Int = 5
    ) throws -> [(String, Double)] {
        let output = try model.predict(input: input)
        var results: [(String, Double)] = []

        for name in output.featureNames {
            if let value = output.featureValue(for: name) {
                switch value.type {
                case .double:
                    results.append((name, value.doubleValue))
                case .int64:
                    results.append((name, Double(value.int64Value)))
                case .multiArray:
                    if let array = value.multiArrayValue {
                        for i in 0..<array.count {
                            results.append(("\(name)_\(i)", array[i].doubleValue))
                        }
                    }
                case .dictionary:
                    if let dict = value.dictionaryValue as? [String: NSNumber] {
                        for (key, val) in dict {
                            results.append((key, val.doubleValue))
                        }
                    }
                default:
                    break
                }
            }
        }

        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(topK))
    }

    /// Runs batch inference on a model.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - inputs: Batch of input feature providers.
    /// - Returns: Batch of predictions.
    /// - Throws: Error if inference fails.
    public func runBatchInference(
        model: OctomilModel,
        inputs: MLBatchProvider
    ) throws -> MLBatchProvider {
        return try model.predict(batch: inputs)
    }

    /// Runs inference with a preprocessing step.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - currentInput: Raw input data.
    ///   - preprocess: Closure that transforms raw input into model-compatible features.
    /// - Returns: Model prediction output.
    /// - Throws: Error if preprocessing or inference fails.
    public func runPipelinedInference(
        model: OctomilModel,
        currentInput: Any,
        preprocess: (Any) throws -> MLFeatureProvider
    ) throws -> MLFeatureProvider {
        let features = try preprocess(currentInput)
        return try model.predict(input: features)
    }

    // MARK: - Private Methods

    /// Emits a new client state.
    private func emitState(_ newState: ClientState) {
        currentState = newState
        stateContinuation?.yield(newState)
    }

    /// Emits a new download state.
    private func emitDownloadState(_ newState: DownloadState) {
        downloadStateContinuation?.yield(newState)
    }

    /// Device info collected during registration.
    private struct LocalDeviceInfo {
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

    private func buildDeviceInfo() async -> LocalDeviceInfo {
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

        let deviceInfo = await MainActor.run {
            (model: UIDevice.current.model, os: UIDevice.current.systemVersion)
        }
        deviceModel = deviceInfo.model
        osVersion = deviceInfo.os
        #else
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        deviceModel = "Mac"
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

    private func generateDeviceIdentifier() -> String {
        #if canImport(UIKit)
        // Use IDFV (Identifier for Vendor) on iOS
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        #endif
        // Fallback to a generated UUID stored in keychain
        if let storedId = try? secureStorage.getClientDeviceIdentifier() {
            return storedId
        }
        let newId = UUID().uuidString
        try? secureStorage.storeClientDeviceIdentifier(newId)
        return newId
    }

    private func hasNeuralEngine() -> Bool {
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
    private func extractShape(from description: MLFeatureDescription) -> [Int] {
        if let constraint = description.multiArrayConstraint {
            return constraint.shape.map { $0.intValue }
        }
        if let imageConstraint = description.imageConstraint {
            return [1, Int(imageConstraint.pixelsHigh), Int(imageConstraint.pixelsWide), 3]
        }
        return []
    }

    /// Returns a string description of a CoreML feature type.
    private func describeFeatureType(_ type: MLFeatureType) -> String {
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
    private func createDummyInput(for model: OctomilModel) -> MLFeatureProvider? {
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
// swiftlint:enable type_body_length

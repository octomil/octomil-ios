import Foundation
import os.log

/// HTTP client for communicating with the Octomil server API.
public actor APIClient {

    // MARK: - API Paths

    private static let defaultVersionAlias = "latest"

    // MARK: - Properties

    private let serverURL: URL
    private let configuration: OctomilConfiguration
    private let session: URLSession
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let logger: Logger
    private let pinningDelegate: CertificatePinningDelegate?

    private var deviceToken: String?

    // MARK: - Initialization

    /// Creates a new API client.
    /// - Parameters:
    ///   - serverURL: The base URL of the Octomil server.
    ///   - configuration: SDK configuration.
    public init(
        serverURL: URL,
        configuration: OctomilConfiguration
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "APIClient")

        // Configure URL session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.downloadTimeout
        sessionConfig.waitsForConnectivity = true
        if configuration.pinnedCertificateHashes.isEmpty {
            self.pinningDelegate = nil
            self.session = URLSession(configuration: sessionConfig)
        } else {
            let delegate = CertificatePinningDelegate(pinnedHashes: configuration.pinnedCertificateHashes)
            self.pinningDelegate = delegate
            self.session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        }

        // Configure JSON decoder
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601

        // Configure JSON encoder
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    /// Creates an API client with an injected URL session configuration (for testing).
    internal init(
        serverURL: URL,
        configuration: OctomilConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "APIClient")

        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.downloadTimeout
        self.session = URLSession(configuration: sessionConfiguration)
        self.pinningDelegate = nil

        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601

        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Token Management

    /// Sets the short-lived device access token for authenticated requests.
    public func setDeviceToken(_ token: String) {
        self.deviceToken = token
    }

    /// Gets the current device token.
    public func getDeviceToken() -> String? {
        return deviceToken
    }

    // MARK: - Device Registration

    /// Registers a device with the server.
    /// - Parameter request: Registration request.
    /// - Returns: Registration response with server-assigned ID.
    public func registerDevice(_ request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/register")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    // MARK: - Device Heartbeat

    /// Sends a heartbeat to the server to indicate device is alive.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - request: Heartbeat request with optional status update.
    /// - Returns: Heartbeat response with updated status.
    public func sendHeartbeat(deviceId: String, request: HeartbeatRequest = HeartbeatRequest()) async throws -> HeartbeatResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/heartbeat")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    // MARK: - Device Groups

    /// Gets the groups this device belongs to.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: List of device groups.
    public func getDeviceGroups(deviceId: String) async throws -> [DeviceGroup] {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/groups")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let response: DeviceGroupsResponse = try await performRequest(urlRequest)
        return response.groups
    }

    /// Gets device information from server.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: Full device information.
    public func getDeviceInfo(deviceId: String) async throws -> DeviceInfo {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Model Operations

    /// Gets the resolved version for a device and model.
    /// - Parameters:
    ///   - deviceId: Device identifier.
    ///   - modelId: Model identifier.
    /// - Returns: Version resolution response.
    public func resolveVersion(deviceId: String, modelId: String) async throws -> VersionResolutionResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/version"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "include_bucket", value: "true")
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets model metadata.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Optional specific version.
    /// - Returns: Model metadata.
    public func getModelMetadata(modelId: String, version: String? = nil) async throws -> ModelMetadata {
        var path = "api/v1/models/\(modelId)/versions"
        if let version = version {
            path += "/\(version)"
        } else {
            path += "/\(Self.defaultVersionAlias)"
        }

        var urlRequest = URLRequest(url: serverURL.appendingPathComponent(path))
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let response: ModelVersionResponse = try await performRequest(urlRequest)
        return ModelMetadata(
            modelId: response.modelId,
            version: response.version,
            checksum: response.checksum,
            fileSize: response.sizeBytes,
            createdAt: response.createdAt,
            format: response.format,
            supportsTraining: true,
            description: response.description,
            inputSchema: nil,
            outputSchema: nil,
            serverContract: response.modelContract
        )
    }

    /// Gets a pre-signed download URL for a model.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    ///   - format: Model format (default: coreml).
    /// - Returns: Download URL response.
    public func getDownloadURL(modelId: String, version: String, format: String = "coreml") async throws -> DownloadURLResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/models/\(modelId)/versions/\(version)/download-url"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: format)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets the device-specific MNN runtime config for optimized inference.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - deviceType: Device profile key (e.g. "iphone_15_pro").
    /// - Returns: MNN config dictionary.
    public func getDeviceConfig(modelId: String, deviceType: String) async throws -> [String: Any] {
        let url = serverURL.appendingPathComponent("api/v1/models/\(modelId)/optimized-config/\(deviceType)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctomilError.unknown(underlying: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OctomilError.serverError(statusCode: httpResponse.statusCode, message: "No optimized config")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OctomilError.decodingError(underlying: "Invalid MNN config response")
        }

        return json
    }

    /// Checks for model updates.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - currentVersion: Current version on device.
    /// - Returns: Update info if available, nil otherwise.
    public func checkForUpdates(modelId: String, currentVersion: String) async throws -> ModelUpdateInfo? {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/models/\(modelId)/updates"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "current_version", value: currentVersion)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        do {
            return try await performRequest(urlRequest)
        } catch OctomilError.serverError(let statusCode, _) where statusCode == 404 {
            // No update available
            return nil
        }
    }

    // MARK: - Health Check

    /// Checks server health.
    /// - Returns: Health response with status.
    public func healthCheck() async throws -> HealthResponse {
        let url = serverURL.appendingPathComponent("health")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        // Health check does not require auth
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        return try await performRequest(urlRequest)
    }

    // MARK: - Model Metadata (full model)

    /// Gets model metadata by ID.
    /// - Parameter modelId: Model identifier.
    /// - Returns: Model response with metadata.
    public func getModel(modelId: String) async throws -> ModelResponse {
        let url = serverURL.appendingPathComponent("api/v1/models/\(modelId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Device Policy

    /// Gets the device policy for an organization.
    /// - Parameter orgId: Organization identifier.
    /// - Returns: Device policy response.
    public func getDevicePolicy(orgId: String) async throws -> DevicePolicyResponse {
        let url = serverURL.appendingPathComponent("api/v1/settings/org/\(orgId)/device-policy")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Round Management

    /// Lists training rounds.
    /// - Parameters:
    ///   - modelId: Model identifier to filter by.
    ///   - state: Round state to filter by (e.g., "waiting_for_updates").
    ///   - deviceId: Device identifier to filter by.
    /// - Returns: List of round assignments.
    public func listRounds(
        modelId: String,
        state: String? = nil,
        deviceId: String? = nil
    ) async throws -> [RoundAssignment] {
        var queryItems = [URLQueryItem(name: "model_id", value: modelId)]
        if let state = state {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        if let deviceId = deviceId {
            queryItems.append(URLQueryItem(name: "device_id", value: deviceId))
        }

        var components = URLComponents(
            url: serverURL.appendingPathComponent("api/v1/training/rounds"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets a specific training round.
    /// - Parameter roundId: Round identifier.
    /// - Returns: Round assignment details.
    public func getRound(roundId: String) async throws -> RoundAssignment {
        let url = serverURL.appendingPathComponent("api/v1/training/rounds/\(roundId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Gradient Submission

    /// Submits gradients for a training round.
    /// - Parameters:
    ///   - experimentId: Experiment or round identifier.
    ///   - request: Gradient update request.
    /// - Returns: Gradient update response.
    public func submitGradients(
        experimentId: String,
        request: GradientUpdateRequest
    ) async throws -> GradientUpdateResponse {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)/gradients")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    // MARK: - Training Operations

    /// Uploads weight updates to the server.
    /// - Parameter update: Weight update to upload.
    public func uploadWeights(_ update: WeightUpdate) async throws {
        let url = serverURL.appendingPathComponent("api/v1/training/weights")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(update)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    /// Tracks a metric on the server.
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - event: Event to track.
    public func trackMetric(experimentId: String, event: TrackingEvent) async throws {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(event)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - Experiments

    /// Fetches all active experiments.
    public func getActiveExperiments() async throws -> [Experiment] {
        let url = serverURL.appendingPathComponent("api/v1/experiments")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Fetches config for a specific experiment.
    public func getExperimentConfig(experimentId: String) async throws -> Experiment {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Inference Events

    /// Reports a streaming inference event to the server (v1 legacy endpoint).
    /// - Parameter request: Inference event request.
    @available(*, deprecated, message: "Use reportTelemetryEvents(_:) with v2 OTLP envelope instead")
    public func reportInferenceEvent(_ request: InferenceEventRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/inference/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - V2 Telemetry

    /// Sends a batch of telemetry events to the v2 OTLP endpoint.
    /// - Parameter envelope: The v2 OTLP telemetry envelope.
    public func reportTelemetryEvents(_ envelope: TelemetryEnvelope) async throws {
        let url = serverURL.appendingPathComponent("api/v2/telemetry/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(envelope)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - Runtime Adaptation

    /// Reports current device state and gets a compute recommendation from the server.
    ///
    /// This allows the server to coordinate adaptation across the fleet, e.g.
    /// recommending specific compute strategies based on global model performance data.
    ///
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - modelId: Model identifier being used for inference.
    ///   - batteryLevel: Current battery level (0.0-1.0).
    ///   - thermalState: Current thermal state string (nominal/fair/serious/critical).
    ///   - currentFormat: Current model format (e.g. "coreml").
    ///   - currentExecutor: Current compute executor (e.g. "all", "cpuAndGPU", "cpuOnly").
    /// - Returns: Server-side adaptation recommendation.
    public func getAdaptationRecommendation(
        deviceId: String,
        modelId: String,
        batteryLevel: Float,
        thermalState: String,
        currentFormat: String,
        currentExecutor: String
    ) async throws -> AdaptationRecommendation {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/adapt")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: Any] = [
            "battery_level": batteryLevel,
            "thermal_state": thermalState,
            "current_format": currentFormat,
            "current_executor": currentExecutor,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performRequest(urlRequest)
    }

    /// Reports a model format/executor failure and requests a fallback.
    ///
    /// When a particular model format or executor fails on-device, this endpoint
    /// tells the server so it can track failure rates and recommend an alternative.
    ///
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - modelId: Model identifier.
    ///   - version: Model version string.
    ///   - failedFormat: The format that failed (e.g. "coreml").
    ///   - failedExecutor: The executor that failed (e.g. "all").
    ///   - errorMessage: Error message from the failure.
    /// - Returns: Server-side fallback recommendation with alternative format/executor.
    public func getFallback(
        deviceId: String,
        modelId: String,
        version: String,
        failedFormat: String,
        failedExecutor: String,
        errorMessage: String
    ) async throws -> FallbackRecommendation {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/fallback")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: String] = [
            "version": version,
            "failed_format": failedFormat,
            "failed_executor": failedExecutor,
            "error_message": errorMessage,
        ]
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }

    // MARK: - Secure Aggregation

    /// Joins a SecAgg session for a training round.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - roundId: The training round to join.
    /// - Returns: Session details including this client's index.
    public func joinSecAggSession(deviceId: String, roundId: String) async throws -> SecAggSessionResponse {
        let url = serverURL.appendingPathComponent("api/v1/secagg/sessions/join")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: String] = ["device_id": deviceId, "round_id": roundId]
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }

    /// Submits key shares for SecAgg Phase 1.
    /// - Parameter request: Share keys request.
    public func submitSecAggShares(_ request: SecAggShareKeysRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/shares")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    /// Submits masked model update for SecAgg Phase 2.
    /// - Parameter request: Masked input request.
    public func submitSecAggMaskedInput(_ request: SecAggMaskedInputRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/masked-input")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    /// Requests unmasking info and submits this client's unmasking shares.
    /// - Parameters:
    ///   - sessionId: SecAgg session identifier.
    ///   - deviceId: Server-assigned device UUID.
    /// - Returns: Unmask response with dropped client indices.
    public func getSecAggUnmaskInfo(sessionId: String, deviceId: String) async throws -> SecAggUnmaskResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/secagg/unmask"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "device_id", value: deviceId)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Submits unmasking data for SecAgg Phase 3.
    /// - Parameter request: Unmask request.
    public func submitSecAggUnmask(_ request: SecAggUnmaskRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/unmask")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - Generic JSON Helpers

    /// Sends a POST request with a JSON body and decodes the response.
    /// - Parameters:
    ///   - path: Relative API path (e.g. "api/v1/federations/{id}/analytics/descriptive").
    ///   - body: Encodable request body.
    /// - Returns: Decoded response.
    public func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let url = serverURL.appendingPathComponent(path)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }

    /// Sends a GET request with optional query items and decodes the response.
    /// - Parameters:
    ///   - path: Relative API path.
    ///   - queryItems: Optional query parameters.
    /// - Returns: Decoded response.
    public func getJSON<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        var components = URLComponents(
            url: serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Download

    /// Downloads data from a URL.
    /// - Parameter url: URL to download from.
    /// - Returns: Downloaded data.
    public func downloadData(from url: URL) async throws -> Data {
        if configuration.enableLogging {
            logger.debug("Downloading from: \(url.absoluteString)")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OctomilError.unknown(underlying: nil)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw OctomilError.downloadFailed(reason: "HTTP \(httpResponse.statusCode)")
                }

                return data
            } catch let error as OctomilError {
                throw error
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    // Exponential backoff
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw OctomilError.downloadFailed(reason: lastError?.localizedDescription ?? "Unknown error")
    }

    // MARK: - Pairing (unauthenticated — the pairing code is the secret)

    /// Poll pairing session status.
    /// - Parameter code: Pairing code from QR scan.
    /// - Returns: Current pairing session state.
    public func getPairingSession(code: String) async throws -> PairingSession {
        let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        return try await performUnauthenticatedRequest(urlRequest)
    }

    /// Connect device to a pairing session.
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - deviceId: Client-generated device UUID.
    ///   - platform: Device platform (e.g. "ios").
    ///   - deviceName: Human-readable device name.
    ///   - chipFamily: SoC family (e.g. "A17 Pro").
    ///   - ramGB: Total RAM in gigabytes.
    ///   - osVersion: OS version string.
    ///   - npuAvailable: Whether NPU is available.
    ///   - gpuAvailable: Whether GPU is available for ML.
    /// - Returns: Updated pairing session.
    public func connectToPairing(
        code: String,
        deviceId: String,
        platform: String,
        deviceName: String,
        chipFamily: String?,
        ramGB: Double?,
        osVersion: String?,
        npuAvailable: Bool?,
        gpuAvailable: Bool?
    ) async throws -> PairingSession {
        let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)/connect")

        var body: [String: Any] = [
            "device_id": deviceId,
            "platform": platform,
            "device_name": deviceName,
        ]
        if let chipFamily = chipFamily { body["chip_family"] = chipFamily }
        if let ramGB = ramGB { body["ram_gb"] = ramGB }
        if let osVersion = osVersion { body["os_version"] = osVersion }
        if let npuAvailable = npuAvailable { body["npu_available"] = npuAvailable }
        if let gpuAvailable = gpuAvailable { body["gpu_available"] = gpuAvailable }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performUnauthenticatedRequest(urlRequest)
    }

    /// Submit benchmark results for a pairing session.
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - report: Benchmark report to submit.
    public func submitPairingBenchmark(code: String, report: BenchmarkReport) async throws {
        let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)/benchmark")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.httpBody = try jsonEncoder.encode(report)

        let _: PairingBenchmarkResponse = try await performUnauthenticatedRequest(urlRequest)
    }

    // MARK: - Private Methods

    /// Performs an HTTP request that does not require authentication.
    /// Used for pairing endpoints where the pairing code serves as the secret.
    private func performUnauthenticatedRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        if configuration.enableLogging {
            logger.debug("Request (unauth): \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctomilError.unknown(underlying: nil)
        }

        if configuration.enableLogging {
            logger.debug("Response: \(httpResponse.statusCode)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 404:
                throw OctomilError.serverError(statusCode: 404, message: errorMessage)
            default:
                throw OctomilError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
        }

        // Handle empty responses
        if T.self == PairingBenchmarkResponse.self, data.isEmpty || data == Data("null".utf8) {
            guard let emptyResult = PairingBenchmarkResponse() as? T else {
                throw OctomilError.decodingError(underlying: "Failed to cast PairingBenchmarkResponse")
            }
            return emptyResult
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw OctomilError.decodingError(underlying: error.localizedDescription)
        }
    }

    private func configureHeaders(_ request: inout URLRequest) throws {
        guard let bearer = deviceToken, !bearer.isEmpty else {
            throw OctomilError.authenticationFailed(reason: "Missing device access token")
        }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        if configuration.enableLogging {
            logger.debug("Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OctomilError.unknown(underlying: nil)
                }

                if configuration.enableLogging {
                    logger.debug("Response: \(httpResponse.statusCode)")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"

                    switch httpResponse.statusCode {
                    case 401:
                        throw OctomilError.invalidAPIKey
                    case 403:
                        throw OctomilError.authenticationFailed(reason: errorMessage)
                    case 404:
                        throw OctomilError.serverError(statusCode: 404, message: errorMessage)
                    default:
                        throw OctomilError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
                    }
                }

                // Handle empty responses
                if T.self == EmptyResponse.self, data.isEmpty || data == Data("null".utf8) {
                    guard let emptyResult = EmptyResponse() as? T else {
                        throw OctomilError.decodingError(underlying: "Failed to cast EmptyResponse")
                    }
                    return emptyResult
                }

                do {
                    return try jsonDecoder.decode(T.self, from: data)
                } catch {
                    throw OctomilError.decodingError(underlying: error.localizedDescription)
                }

            } catch let error as OctomilError {
                // Don't retry Octomil errors
                throw error
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw OctomilError.networkUnavailable
                case .timedOut:
                    throw OctomilError.requestTimeout
                case .cancelled:
                    throw OctomilError.cancelled
                default:
                    lastError = error
                    retries += 1
                    if retries < configuration.maxRetryAttempts {
                        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                    }
                }
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw OctomilError.unknown(underlying: lastError)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let errorResponse = try? jsonDecoder.decode(APIErrorResponse.self, from: data) {
            return errorResponse.detail
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Empty Response

private struct EmptyResponse: Decodable {}

// MARK: - Pairing Benchmark Response

/// Empty response from the benchmark submission endpoint.
/// The server may return an empty body or a simple acknowledgment.
struct PairingBenchmarkResponse: Decodable {
    init() {}
}

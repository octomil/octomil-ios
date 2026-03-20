import Foundation
import os.log

/// Manages the QR code pairing flow for deploying models to this device.
///
/// The pairing flow is:
/// 1. User scans a QR code on the Octomil dashboard
/// 2. Device connects to the pairing session with its capabilities
/// 3. Server prepares an optimized model variant for this device
/// 4. Device downloads and persists the model
///
/// Real performance benchmarks are collected later by the Deploy (engine routing)
/// layer when the model is loaded for inference.
///
/// # Example Usage
///
/// ```swift
/// let manager = PairingManager(serverURL: URL(string: "https://api.octomil.com")!)
/// let result = try await manager.pair(code: "ABC123")
/// print("Model at: \(result.persistedModelURL)")
/// ```
public actor PairingManager {

    // MARK: - Properties

    private let apiClient: APIClient
    private let configuration: OctomilConfiguration
    private let logger: Logger

    /// Default polling interval in seconds when waiting for deployment.
    private static let defaultPollInterval: TimeInterval = 2.0

    // MARK: - Initialization

    /// Creates a new pairing manager.
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    public init(apiClient: APIClient, configuration: OctomilConfiguration = .standard) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingManager")
    }

    /// Convenience initializer that creates its own API client.
    /// - Parameters:
    ///   - serverURL: Base URL of the Octomil server.
    ///   - configuration: SDK configuration.
    public init(serverURL: URL, configuration: OctomilConfiguration = .standard) {
        self.apiClient = APIClient(serverURL: serverURL, configuration: configuration)
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingManager")
    }

    /// Test-only initializer with injected URLSession configuration.
    internal init(
        serverURL: URL,
        configuration: OctomilConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.apiClient = APIClient(
            serverURL: serverURL,
            configuration: configuration,
            sessionConfiguration: sessionConfiguration
        )
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingManager")
    }

    // MARK: - Public API

    /// Connect to a pairing session using the code from a QR scan.
    ///
    /// Sends device capabilities to the server so it can select the
    /// optimal model variant for this hardware.
    ///
    /// - Parameters:
    ///   - code: Pairing code from the QR scan.
    ///   - deviceCapabilities: Device hardware info. Defaults to auto-detected.
    /// - Returns: The pairing session info.
    /// - Throws: ``PairingError`` or ``OctomilError``.
    public func connect(
        code: String,
        deviceCapabilities: PairingDeviceCapabilities = .current()
    ) async throws -> PairingSession {
        if configuration.enableLogging {
            logger.info("Connecting to pairing session: \(code)")
        }

        let session: PairingSession
        do {
            session = try await apiClient.connectToPairing(
                code: code,
                deviceId: UUID().uuidString,
                platform: "ios",
                deviceName: deviceCapabilities.deviceName,
                chipFamily: deviceCapabilities.chipFamily,
                ramGB: deviceCapabilities.ramGB,
                osVersion: deviceCapabilities.osVersion,
                npuAvailable: deviceCapabilities.npuAvailable,
                gpuAvailable: deviceCapabilities.gpuAvailable,
                locale: deviceCapabilities.locale,
                region: deviceCapabilities.region,
                timezone: deviceCapabilities.timezone
            )
        } catch let error as OctomilError {
            // Map server errors that indicate "session already used" to a typed pairing error.
            switch error {
            case .serverError(409, _):
                throw PairingError.sessionAlreadyUsed
            case .invalidInput(let reason) where reason.lowercased().contains("already"):
                throw PairingError.sessionAlreadyUsed
            default:
                throw error
            }
        }

        if configuration.enableLogging {
            logger.info("Connected to session \(session.id), model: \(session.modelName)")
        }

        TelemetryQueue.shared?.reportFunnelEvent(
            stage: "app_pair",
            success: true,
            deviceId: UUID().uuidString,
            platform: "ios"
        )

        return session
    }

    /// Poll for deployment status until a model is ready to download.
    ///
    /// Blocks until the session reaches `deploying` or `done` status,
    /// or until the timeout expires.
    ///
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - timeout: Maximum time to wait in seconds (default: 300).
    /// - Returns: Deployment info with download URL.
    /// - Throws: ``PairingError/deploymentTimeout`` if timeout expires.
    ///           ``PairingError/sessionExpired`` if session expires.
    ///           ``PairingError/sessionCancelled`` if session is cancelled.
    public func waitForDeployment(
        code: String,
        timeout: TimeInterval = 300
    ) async throws -> DeploymentInfo {
        if configuration.enableLogging {
            logger.info("Waiting for deployment on session \(code), timeout=\(timeout)s")
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let session = try await apiClient.getPairingSession(code: code)

            switch session.status {
            case .deploying, .done:
                guard let downloadURL = session.downloadURL,
                      let format = session.downloadFormat else {
                    throw PairingError.invalidDeployment(
                        reason: "Session is deploying but missing download URL or format"
                    )
                }

                let deployment = DeploymentInfo(
                    modelName: session.modelName,
                    modelVersion: session.modelVersion ?? "latest",
                    downloadURL: downloadURL,
                    format: format,
                    quantization: session.quantization,
                    executor: session.executor,
                    sizeBytes: session.downloadSizeBytes,
                    resources: session.resources
                )

                if configuration.enableLogging {
                    logger.info("Deployment ready: \(session.modelName) (\(format))")
                }

                return deployment

            case .expired:
                throw PairingError.sessionExpired

            case .cancelled:
                throw PairingError.sessionCancelled

            case .error:
                throw PairingError.invalidDeployment(
                    reason: "Server encountered an error preparing the deployment"
                )

            case .pending, .connected:
                // Keep polling
                try await Task.sleep(nanoseconds: UInt64(Self.defaultPollInterval * 1_000_000_000))
            }
        }

        throw PairingError.deploymentTimeout
    }

    /// Download model resources and persist them to disk.
    ///
    /// - Parameters:
    ///   - deployment: Deployment info from ``waitForDeployment(code:timeout:)``.
    ///   - progress: Called as data arrives with `(bytesDownloaded, totalBytes)`.
    /// - Returns: A ``DeploymentResult`` with the persisted model URL and metadata.
    /// - Throws: ``PairingError`` if download fails.
    public func executeDeployment(
        _ deployment: DeploymentInfo,
        progress: @Sendable @escaping (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> DeploymentResult {
        guard let resources = deployment.resources, !resources.isEmpty else {
            throw PairingError.invalidDeployment(reason: "No resources in deployment")
        }

        if configuration.enableLogging {
            logger.info("Executing deployment: \(deployment.modelName) (\(resources.count) resources)")
        }

        return try await executeMultiResourceDeployment(deployment, resources: resources, progress: progress)
    }

    /// Downloads multiple resources into a model directory and persists them.
    ///
    /// Runtime-specific loading (CoreML compilation, ONNX init, etc.)
    /// is handled by the engine abstraction, not here.
    private func executeMultiResourceDeployment(
        _ deployment: DeploymentInfo,
        resources: [DownloadResource],
        progress: @Sendable @escaping (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> DeploymentResult {
        let downloadStart = Date()
        let fm = FileManager.default
        let modelDir = fm.temporaryDirectory
            .appendingPathComponent("ai.octomil.deploy", isDirectory: true)
            .appendingPathComponent(deployment.modelName, isDirectory: true)

        try fm.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let sortedResources = resources.sorted { $0.loadOrder < $1.loadOrder }
        let totalSize = Int64(sortedResources.compactMap(\.sizeBytes).reduce(0, +))
        var completedBytes: Int64 = 0

        for resource in sortedResources {
            guard let resourceURL = URL(string: resource.uri) else {
                throw PairingError.invalidDeployment(
                    reason: "Invalid resource URI: \(resource.uri)"
                )
            }

            if configuration.enableLogging {
                logger.info("Downloading resource [\(resource.loadOrder)]: \(resource.filename) (\(resource.kind))")
            }

            let fileURL = modelDir.appendingPathComponent(resource.filename)
            let resourceSize = Int64(resource.sizeBytes ?? 0)
            let capturedCompleted = completedBytes

            do {
                try await apiClient.downloadFile(
                    from: resourceURL,
                    to: fileURL,
                    expectedBytes: resourceSize
                ) { written, fileTotal in
                    let currentTotal = capturedCompleted + written
                    let effectiveTotal = totalSize > 0 ? totalSize : fileTotal
                    progress(currentTotal, effectiveTotal)
                }
            } catch {
                try? fm.removeItem(at: modelDir)
                throw PairingError.downloadFailed(
                    reason: "Failed to download resource '\(resource.filename)': \(error.localizedDescription)"
                )
            }

            if resourceSize > 0 {
                completedBytes += resourceSize
            } else {
                let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
                completedBytes += Int64((attrs?[.size] as? UInt64) ?? 0)
            }
        }

        // Report 100%
        let finalTotal = totalSize > 0 ? totalSize : completedBytes
        progress(finalTotal, finalTotal)

        // Build resource bindings from downloaded resources (kind → filename)
        var bindings: [String: String] = [:]
        for resource in sortedResources {
            bindings[resource.kind] = resource.filename
        }

        // Persist downloaded files to model cache
        let persistedURL = try Self.persistModelDirectory(
            sourceDir: modelDir,
            modelName: deployment.modelName,
            version: deployment.modelVersion
        )

        let downloadTimeMs = Date().timeIntervalSince(downloadStart) * 1000

        if configuration.enableLogging {
            logger.info("Model persisted to: \(persistedURL.path) (\(String(format: "%.0f", downloadTimeMs))ms)")
        }

        return DeploymentResult(
            modelName: deployment.modelName,
            modelVersion: deployment.modelVersion,
            persistedModelURL: persistedURL,
            downloadTimeMs: downloadTimeMs,
            executor: deployment.executor,
            resourceBindings: bindings
        )
    }

    /// Full pairing flow: connect, wait for deployment, and download.
    ///
    /// This is the recommended single-call API for the pairing flow.
    /// Real performance benchmarks are submitted later by the Deploy layer
    /// when the model is loaded for inference.
    ///
    /// - Parameters:
    ///   - code: Pairing code from QR scan.
    ///   - deviceCapabilities: Device hardware info. Defaults to auto-detected.
    ///   - timeout: Maximum time to wait for deployment in seconds.
    /// - Returns: A ``DeploymentResult`` with the persisted model URL and metadata.
    /// - Throws: ``PairingError`` or ``OctomilError``.
    public func pair(
        code: String,
        deviceCapabilities: PairingDeviceCapabilities = .current(),
        timeout: TimeInterval = 300
    ) async throws -> DeploymentResult {
        if configuration.enableLogging {
            logger.info("Starting full pairing flow for code: \(code)")
        }

        // Step 1: Connect
        _ = try await connect(code: code, deviceCapabilities: deviceCapabilities)

        // Step 2: Wait for deployment
        let deployment = try await waitForDeployment(code: code, timeout: timeout)

        // Step 3: Download and persist
        let result = try await executeDeployment(deployment)

        if configuration.enableLogging {
            logger.info("Pairing flow complete for code: \(code)")
        }

        return result
    }

    // MARK: - Model Persistence

    /// Moves a model directory to persistent storage.
    ///
    /// Path: `~/Library/Application Support/ai.octomil.models/{name}/{version}/`
    private static func persistModelDirectory(
        sourceDir: URL,
        modelName: String,
        version: String
    ) throws -> URL {
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let targetDir = cacheDir
            .appendingPathComponent("ai.octomil.models", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)

        // Remove existing model directory if present
        if fm.fileExists(atPath: targetDir.path) {
            try fm.removeItem(at: targetDir)
        }

        // Ensure parent exists
        try fm.createDirectory(
            at: targetDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Move entire directory (more efficient than copy)
        try fm.moveItem(at: sourceDir, to: targetDir)

        return targetDir
    }

}

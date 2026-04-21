import Foundation
import CoreML
import os.log
import CryptoKit

/// Manages model download, caching, and version control.
public actor ModelManager {

    // MARK: - Properties

    private let apiClient: APIClient
    private let modelCache: any ModelCaching
    private let configuration: OctomilConfiguration
    private let profileClient: DeviceProfileClient?
    private let logger: Logger
    private let fileManager = FileManager.default
    private let deviceMetadata = DeviceMetadata()

    private var downloadTasks: [String: Task<OctomilModel, Error>] = [:]

    // MARK: - Initialization

    /// Creates a new model manager.
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    ///   - profileClient: Client for fetching server-provided device profiles. Pass `nil` to use RAM-based fallback.
    internal init(
        apiClient: APIClient,
        configuration: OctomilConfiguration,
        profileClient: DeviceProfileClient? = nil
    ) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.modelCache = ModelCache(maxSize: configuration.maxCacheSize)
        self.profileClient = profileClient
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelManager")
    }

    /// Creates a new model manager with an injected cache (for testing).
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    ///   - modelCache: Cache implementation.
    ///   - profileClient: Client for fetching server-provided device profiles. Pass `nil` to use RAM-based fallback.
    internal init(
        apiClient: APIClient,
        configuration: OctomilConfiguration,
        modelCache: any ModelCaching,
        profileClient: DeviceProfileClient? = nil
    ) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.modelCache = modelCache
        self.profileClient = profileClient
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelManager")
    }

    // MARK: - Download

    /// Downloads a model from the server.
    ///
    /// If a download is already in progress for this model, returns the existing task.
    ///
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    /// - Returns: Downloaded model.
    /// - Throws: `OctomilError` if download fails.
    public func downloadModel(modelId: String, version: String) async throws -> OctomilModel {
        let cacheKey = "\(modelId)_\(version)"

        // Check if already downloading
        if let existingTask = downloadTasks[cacheKey] {
            return try await existingTask.value
        }

        // Check cache first
        if let cached = modelCache.get(modelId: modelId, version: version) {
            if configuration.enableLogging {
                logger.debug("Model found in cache: \(modelId)@\(version)")
            }
            return cached
        }

        // Start download task
        let task = Task<OctomilModel, Error> {
            defer {
                Task {
                    await self.removeDownloadTask(cacheKey)
                }
            }

            // Record deploy started telemetry
            TelemetryQueue.shared?.reportDeployStarted(modelId: modelId, version: version)
            let deployStart = CFAbsoluteTimeGetCurrent()

            // Get metadata
            let metadata = try await apiClient.getModelMetadata(modelId: modelId, version: version)

            // Resolve device profile: server-provided mapping if available, else RAM-based tier
            let deviceProfile: String
            if let profileClient = self.profileClient {
                deviceProfile = await self.deviceMetadata.resolveDeviceProfile(using: profileClient)
            } else {
                deviceProfile = self.deviceMetadata.deviceProfile
            }

            // Resolve optimal model format from device capabilities.
            let resolveRequest = ModelResolveRequest(
                platform: "ios",
                model: self.deviceMetadata.model,
                manufacturer: self.deviceMetadata.manufacturer,
                cpuArchitecture: self.deviceMetadata.cpuArchitecture,
                osVersion: self.deviceMetadata.osVersion,
                totalMemoryMb: self.deviceMetadata.totalMemoryMB,
                gpuAvailable: self.deviceMetadata.gpuAvailable,
                npuAvailable: self.deviceMetadata.gpuAvailable,
                supportedRuntimes: ["coreml"],
                computeUnits: "all"
            )

            let resolution = try await apiClient.resolveModelFormat(
                modelId: modelId,
                version: version,
                capabilities: resolveRequest
            )
            let resolvedFormat = resolution.format
            let downloadInfo = try await apiClient.getDownloadURL(
                modelId: modelId,
                version: resolution.version,
                format: resolvedFormat
            )

            guard let downloadURL = URL(string: downloadInfo.url) else {
                throw OctomilError.invalidRequest(reason: "Invalid download URL")
            }

            // Download model file
            let modelData = try await apiClient.downloadData(from: downloadURL)

            // Verify checksum
            let checksum = SHA256.hash(data: modelData).compactMap { String(format: "%02x", $0) }.joined()
            guard checksum == downloadInfo.checksum else {
                throw OctomilError.checksumMismatch
            }

            // Save to temporary file
            let tempDir = fileManager.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("\(modelId)_\(version).mlmodel")
            try modelData.write(to: tempFile)

            // Compile model
            let compiledURL: URL
            do {
                compiledURL = try await MLModel.compileModel(at: tempFile)
            } catch {
                throw OctomilError.modelCompilationFailed(reason: error.localizedDescription)
            }

            // Move to cache directory
            let cacheURL = try await self.modelCache.cacheCompiledModel(
                modelId: modelId,
                version: version,
                compiledURL: compiledURL
            )

            // Load model
            let mlModel: MLModel
            do {
                mlModel = try MLModel(contentsOf: cacheURL)
            } catch {
                throw OctomilError.modelCompilationFailed(reason: error.localizedDescription)
            }

            // Clean up temp file
            try? fileManager.removeItem(at: tempFile)

            // Create OctomilModel
            let model = OctomilModel(
                id: modelId,
                version: version,
                mlModel: mlModel,
                metadata: metadata,
                compiledModelURL: cacheURL
            )

            // Store in memory cache
            await self.modelCache.store(model)

            // Fetch device-specific MNN runtime config if available
            do {
                let mnnConfig = try await self.apiClient.getDeviceConfig(
                    modelId: modelId,
                    deviceType: deviceProfile
                )
                model.mnnConfig = mnnConfig
            } catch {
                // No MNN config available — standard CoreML runtime
                if self.configuration.enableLogging {
                    self.logger.debug("No MNN config for \(modelId) on \(deviceProfile)")
                }
            }

            // Record deploy completed telemetry
            let deployDurationMs = (CFAbsoluteTimeGetCurrent() - deployStart) * 1000
            TelemetryQueue.shared?.reportDeployCompleted(
                modelId: modelId,
                version: version,
                durationMs: deployDurationMs
            )

            if self.configuration.enableLogging {
                self.logger.info("Model downloaded: \(modelId)@\(version)")
            }

            TelemetryQueue.shared?.reportFunnelEvent(
                stage: "first_deploy",
                success: true,
                modelId: modelId
            )

            return model
        }

        downloadTasks[cacheKey] = task
        return try await task.value
    }

    private func removeDownloadTask(_ key: String) {
        downloadTasks[key] = nil
    }

    // MARK: - Asset Status

    /// Checks the readiness of a local model asset without triggering a download.
    ///
    /// Use this to determine what action is needed before inference can proceed.
    /// The result is idempotent: calling this a second time after a successful
    /// download returns `.ready` without re-downloading.
    ///
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    /// - Returns: The current ``LocalAssetStatus`` for the model.
    public func checkAssetStatus(modelId: String, version: String) async -> LocalAssetStatus {
        // Check if currently downloading
        let cacheKey = "\(modelId)_\(version)"
        if downloadTasks[cacheKey] != nil {
            return .preparing(progress: nil)
        }

        // Check memory + disk cache
        if let cached = modelCache.get(modelId: modelId, version: version) {
            return .ready(localURL: cached.compiledModelURL)
        }

        // Not cached — determine if a download is possible
        do {
            let metadata = try await apiClient.getModelMetadata(modelId: modelId, version: version)
            let sizeBytes = Int64(metadata.fileSize)

            let resolveRequest = ModelResolveRequest(
                platform: "ios",
                model: deviceMetadata.model,
                manufacturer: deviceMetadata.manufacturer,
                cpuArchitecture: deviceMetadata.cpuArchitecture,
                osVersion: deviceMetadata.osVersion,
                totalMemoryMb: deviceMetadata.totalMemoryMB,
                gpuAvailable: deviceMetadata.gpuAvailable,
                npuAvailable: deviceMetadata.gpuAvailable,
                supportedRuntimes: ["coreml"],
                computeUnits: "all"
            )
            let resolution = try await apiClient.resolveModelFormat(
                modelId: modelId,
                version: version,
                capabilities: resolveRequest
            )
            let downloadInfo = try await apiClient.getDownloadURL(
                modelId: modelId,
                version: resolution.version,
                format: resolution.format
            )
            guard let downloadURL = URL(string: downloadInfo.url) else {
                return .unavailable(reason: "Invalid download URL for model \(modelId)@\(version)")
            }
            return .downloadRequired(url: downloadURL, sizeBytes: sizeBytes)
        } catch {
            return .unavailable(reason: "Cannot resolve model \(modelId)@\(version): \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Access

    /// Gets a cached model.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Optional version. Returns latest cached if nil.
    /// - Returns: Cached model or nil if not found.
    public nonisolated func getCachedModel(modelId: String) -> OctomilModel? {
        return modelCache.getLatest(modelId: modelId)
    }

    /// Gets a cached model with specific version.
    public nonisolated func getCachedModel(modelId: String, version: String) -> OctomilModel? {
        return modelCache.get(modelId: modelId, version: version)
    }

    /// Clears all cached models.
    public func clearCache() throws {
        try modelCache.clearAll()
    }

    /// Gets the size of the cache in bytes.
    public nonisolated func getCacheSize() -> UInt64 {
        return modelCache.currentSize
    }
}

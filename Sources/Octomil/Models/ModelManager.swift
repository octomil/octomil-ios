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
    private let logger: Logger
    private let fileManager = FileManager.default
    private let deviceMetadata = DeviceMetadata()

    private var downloadTasks: [String: Task<OctomilModel, Error>] = [:]

    // MARK: - Initialization

    /// Creates a new model manager.
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    internal init(apiClient: APIClient, configuration: OctomilConfiguration) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.modelCache = ModelCache(maxSize: configuration.maxCacheSize)
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelManager")
    }

    /// Creates a new model manager with an injected cache (for testing).
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    ///   - modelCache: Cache implementation.
    internal init(apiClient: APIClient, configuration: OctomilConfiguration, modelCache: any ModelCaching) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.modelCache = modelCache
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

            // Get metadata
            let metadata = try await apiClient.getModelMetadata(modelId: modelId, version: version)

            // Auto-detect device profile for optimal format selection
            let deviceProfile = self.deviceMetadata.deviceProfile

            // Get download URL — always CoreML on iOS
            let downloadInfo = try await apiClient.getDownloadURL(
                modelId: modelId,
                version: version,
                format: "coreml"
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
                compiledURL = try MLModel.compileModel(at: tempFile)
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

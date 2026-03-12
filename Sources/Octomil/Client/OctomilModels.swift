import Foundation
import CoreML
import os.log

/// Namespace client for model lifecycle operations.
///
/// Access via ``OctomilClient/models``:
///
/// ```swift
/// let model = try await client.models.load("fraud_detection")
/// let cached = client.models.list()
/// let status = client.models.status("fraud_detection")
/// client.models.unload("fraud_detection")
/// try await client.models.clearCache()
/// ```
public final class OctomilModels: @unchecked Sendable {

    // MARK: - Properties

    private let modelManager: ModelManager
    private let apiClient: APIClient
    private let configuration: OctomilConfiguration
    private let logger: Logger
    /// Resolves device ID lazily from the parent client.
    private let deviceIdProvider: () -> String?

    /// Models that have been loaded into memory via ``load(_:version:)``.
    private let lock = NSLock()
    private var loadedModels: [String: OctomilModel] = [:]

    // MARK: - Initialization

    internal init(
        modelManager: ModelManager,
        apiClient: APIClient,
        configuration: OctomilConfiguration,
        deviceIdProvider: @escaping () -> String?
    ) {
        self.modelManager = modelManager
        self.apiClient = apiClient
        self.configuration = configuration
        self.deviceIdProvider = deviceIdProvider
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "OctomilModels")
    }

    // MARK: - Load

    /// Downloads (or retrieves from cache) a model and loads it into memory.
    ///
    /// This is the primary way to obtain an ``OctomilModel`` for inference.
    /// If the model is already cached locally and no version is specified,
    /// the cached version is returned without a network call.
    ///
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Specific version to load. If `nil`, resolves the latest.
    /// - Returns: A loaded ``OctomilModel`` ready for inference.
    /// - Throws: ``OctomilError`` if download or loading fails.
    public func load(_ modelId: String, version: String? = nil) async throws -> OctomilModel {
        // If already loaded in memory with matching version, return it
        lock.lock()
        if let existing = loadedModels[modelId] {
            if version == nil || existing.version == version {
                lock.unlock()
                return existing
            }
        }
        lock.unlock()

        let model: OctomilModel
        if let version = version {
            // Check cache first
            if let cached = modelManager.getCachedModel(modelId: modelId, version: version) {
                model = cached
            } else {
                model = try await modelManager.downloadModel(modelId: modelId, version: version)
            }
        } else {
            // Check cache for any version
            if let cached = modelManager.getCachedModel(modelId: modelId) {
                model = cached
            } else {
                // Resolve version from server
                guard let deviceId = deviceIdProvider() else {
                    throw OctomilError.deviceNotRegistered
                }
                let resolution = try await apiClient.resolveVersion(deviceId: deviceId, modelId: modelId)
                model = try await modelManager.downloadModel(modelId: modelId, version: resolution.version)
            }
        }

        lock.lock()
        loadedModels[modelId] = model
        lock.unlock()

        if configuration.enableLogging {
            logger.info("Model loaded: \(modelId)@\(model.version)")
        }

        return model
    }

    // MARK: - Status

    /// Returns the local cache status for a model.
    ///
    /// - Parameter modelId: Model identifier.
    /// - Returns: The current ``ModelStatus``.
    public func status(_ modelId: String) -> ModelStatus {
        lock.lock()
        let isLoaded = loadedModels[modelId] != nil
        lock.unlock()

        if isLoaded {
            return .ready
        }

        if modelManager.getCachedModel(modelId: modelId) != nil {
            return .ready
        }

        return .notCached
    }

    // MARK: - Unload

    /// Releases a model from runtime memory.
    ///
    /// The model remains in the disk cache and can be re-loaded via ``load(_:version:)``.
    /// This is useful for freeing memory when a model is no longer actively needed.
    ///
    /// - Parameter modelId: Model identifier to unload.
    public func unload(_ modelId: String) {
        lock.lock()
        loadedModels.removeValue(forKey: modelId)
        lock.unlock()

        if configuration.enableLogging {
            logger.info("Model unloaded from memory: \(modelId)")
        }
    }

    // MARK: - List

    /// Lists all locally cached models.
    ///
    /// Returns metadata about each cached model without loading them into memory.
    ///
    /// - Returns: Array of ``CachedModel`` entries describing each cached model.
    public func list() -> [CachedModel] {
        let cacheDir: URL
        let fm = FileManager.default
        let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = cachesDir.appendingPathComponent("ai.octomil.models", isDirectory: true)

        guard fm.fileExists(atPath: cacheDir.path) else {
            return []
        }

        var results: [CachedModel] = []

        guard let modelDirs = try? fm.contentsOfDirectory(atPath: cacheDir.path) else {
            return []
        }

        for modelId in modelDirs {
            let modelDir = cacheDir.appendingPathComponent(modelId)
            guard let versions = try? fm.contentsOfDirectory(atPath: modelDir.path) else {
                continue
            }
            for version in versions {
                let modelPath = modelDir
                    .appendingPathComponent(version)
                    .appendingPathComponent("model.mlmodelc")
                guard fm.fileExists(atPath: modelPath.path) else { continue }

                let sizeBytes = directorySize(at: modelPath, fileManager: fm)

                lock.lock()
                let isLoaded = loadedModels[modelId]?.version == version
                lock.unlock()

                results.append(CachedModel(
                    modelId: modelId,
                    version: version,
                    sizeBytes: sizeBytes,
                    isLoaded: isLoaded
                ))
            }
        }

        return results
    }

    // MARK: - Clear Cache

    /// Removes all cached models from disk and unloads them from memory.
    ///
    /// - Throws: If cache removal fails.
    public func clearCache() async throws {
        lock.lock()
        loadedModels.removeAll()
        lock.unlock()

        try await modelManager.clearCache()

        if configuration.enableLogging {
            logger.info("All model cache cleared")
        }
    }

    // MARK: - Private

    private func directorySize(at url: URL, fileManager: FileManager) -> UInt64 {
        var size: UInt64 = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += UInt64(fileSize)
            }
        }
        return size
    }
}

// MARK: - CachedModel

/// Metadata about a model stored in the local cache.
public struct CachedModel: Sendable {
    /// Model identifier.
    public let modelId: String
    /// Cached version string.
    public let version: String
    /// Size of the cached model on disk in bytes.
    public let sizeBytes: UInt64
    /// Whether this model is currently loaded in runtime memory.
    public let isLoaded: Bool

    public init(
        modelId: String,
        version: String,
        sizeBytes: UInt64,
        isLoaded: Bool
    ) {
        self.modelId = modelId
        self.version = version
        self.sizeBytes = sizeBytes
        self.isLoaded = isLoaded
    }
}

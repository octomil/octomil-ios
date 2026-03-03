import Foundation
import os.log

/// Protocol for model caching operations.
protocol ModelCaching: Sendable {
    func get(modelId: String, version: String) -> OctomilModel?
    func getLatest(modelId: String) -> OctomilModel?
    func store(_ model: OctomilModel)
    func cacheCompiledModel(modelId: String, version: String, compiledURL: URL) async throws -> URL
    func clearAll() throws
    var currentSize: UInt64 { get }
}

/// Manages the local cache of downloaded models.
public final class ModelCache: ModelCaching, @unchecked Sendable {

    // MARK: - Properties

    private let maxSize: UInt64
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let logger: Logger

    private var memoryCache: [String: OctomilModel] = [:]
    private var accessOrder: [String] = []
    private let lock = NSLock()

    /// Current size of cached files on disk in bytes.
    public var currentSize: UInt64 {
        return calculateCacheSize()
    }

    // MARK: - Initialization

    /// Creates a new model cache.
    /// - Parameter maxSize: Maximum cache size in bytes.
    internal init(maxSize: UInt64) {
        self.maxSize = maxSize
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelCache")

        // Get cache directory
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("ai.octomil.models", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Cache Operations

    /// Stores a model in the memory cache.
    /// - Parameter model: Model to store.
    internal func store(_ model: OctomilModel) {
        let key = cacheKey(modelId: model.id, version: model.version)

        lock.lock()
        defer { lock.unlock() }

        memoryCache[key] = model

        // Update access order (LRU)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)

        // Evict if over memory limit (keep 10 most recent)
        while accessOrder.count > 10 {
            let oldestKey = accessOrder.removeFirst()
            memoryCache.removeValue(forKey: oldestKey)
        }
    }

    /// Gets a model from cache.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    /// - Returns: Cached model or nil.
    internal func get(modelId: String, version: String) -> OctomilModel? {
        let key = cacheKey(modelId: modelId, version: version)

        lock.lock()
        defer { lock.unlock() }

        if let model = memoryCache[key] {
            // Update access order
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)
            return model
        }

        // Try to load from disk
        let diskPath = modelPath(modelId: modelId, version: version)
        if fileManager.fileExists(atPath: diskPath.path) {
            return loadModelFromDisk(modelId: modelId, version: version, path: diskPath)
        }

        return nil
    }

    /// Gets the latest cached version of a model.
    /// - Parameter modelId: Model identifier.
    /// - Returns: Latest cached model or nil.
    internal func getLatest(modelId: String) -> OctomilModel? {
        lock.lock()
        let cachedModels = memoryCache.filter { $0.value.id == modelId }
        lock.unlock()

        if let latest = cachedModels.values.sorted(by: { compareVersions($0.version, $1.version) }).last {
            return latest
        }

        // Check disk cache
        let modelDir = cacheDirectory.appendingPathComponent(modelId)
        guard fileManager.fileExists(atPath: modelDir.path),
              let versions = try? fileManager.contentsOfDirectory(atPath: modelDir.path) else {
            return nil
        }

        if let latestVersion = versions.sorted(by: { compareVersions($0, $1) }).last {
            return get(modelId: modelId, version: latestVersion)
        }

        return nil
    }

    /// Caches a compiled model to disk.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    ///   - compiledURL: URL of the compiled model.
    /// - Returns: URL where the model was cached.
    internal func cacheCompiledModel(modelId: String, version: String, compiledURL: URL) async throws -> URL {
        // Ensure we have enough space
        try await evictIfNeeded()

        let targetDir = modelPath(modelId: modelId, version: version)

        // Create parent directory
        let parentDir = targetDir.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Remove existing if present
        if fileManager.fileExists(atPath: targetDir.path) {
            try fileManager.removeItem(at: targetDir)
        }

        // Copy compiled model
        try fileManager.copyItem(at: compiledURL, to: targetDir)

        // Clean up original compiled model
        try? fileManager.removeItem(at: compiledURL)

        logger.debug("Cached model at: \(targetDir.path)")

        return targetDir
    }

    /// Clears all cached models.
    internal func clearAll() throws {
        lock.lock()
        memoryCache.removeAll()
        accessOrder.removeAll()
        lock.unlock()

        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        logger.info("Cache cleared")
    }

    /// Removes a specific model from cache.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    internal func remove(modelId: String, version: String) throws {
        let key = cacheKey(modelId: modelId, version: version)

        lock.lock()
        memoryCache.removeValue(forKey: key)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        lock.unlock()

        let path = modelPath(modelId: modelId, version: version)
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    // MARK: - Private Methods

    private func cacheKey(modelId: String, version: String) -> String {
        return "\(modelId)_\(version)"
    }

    private func modelPath(modelId: String, version: String) -> URL {
        return cacheDirectory
            .appendingPathComponent(modelId)
            .appendingPathComponent(version)
            .appendingPathComponent("model.mlmodelc")
    }

    private func loadModelFromDisk(modelId: String, version: String, path: URL) -> OctomilModel? {
        do {
            let mlModel = try MLModel(contentsOf: path)

            // Create placeholder metadata — use "auto" rather than hardcoding a
            // specific format; the actual format is resolved server-side.
            let metadata = ModelMetadata(
                modelId: modelId,
                version: version,
                checksum: "",
                fileSize: 0,
                createdAt: Date(),
                format: "auto",
                supportsTraining: mlModel.modelDescription.isUpdatable,
                description: nil,
                inputSchema: nil,
                outputSchema: nil
            )

            let model = OctomilModel(
                id: modelId,
                version: version,
                mlModel: mlModel,
                metadata: metadata,
                compiledModelURL: path
            )

            store(model)
            return model
        } catch {
            logger.error("Failed to load model from disk: \(error.localizedDescription)")
            return nil
        }
    }

    private func calculateCacheSize() -> UInt64 {
        var size: UInt64 = 0

        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
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

    private func evictIfNeeded() async throws {
        let currentSize = calculateCacheSize()
        guard currentSize > maxSize else { return }

        // Get all cached models with their modification dates
        var models: [(path: URL, date: Date)] = []

        if let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) {
            for case let modelDir as URL in enumerator {
                if let modDate = try? modelDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    models.append((modelDir, modDate))
                }
            }
        }

        // Sort by oldest first
        models.sort { $0.date < $1.date }

        // Remove oldest until under limit
        var removedSize: UInt64 = 0
        let targetRemoval = currentSize - (maxSize * 8 / 10) // Target 80% of max

        for (path, _) in models {
            guard removedSize < targetRemoval else { break }

            if let size = try? fileManager.attributesOfItem(atPath: path.path)[.size] as? UInt64 {
                removedSize += size
            }

            try? fileManager.removeItem(at: path)
            logger.debug("Evicted: \(path.lastPathComponent)")
        }
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 < p2 { return true }
            if p1 > p2 { return false }
        }

        return false
    }
}

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil

/// Actor responsible for loading and caching MLX models.
///
/// Supports loading from local directories (config.json + safetensors) or
/// from HuggingFace Hub for development/testing.
@available(iOS 17.0, macOS 14.0, *)
public actor MLXModelLoader {

    /// Cache directory for MLX models (Application Support — non-purgeable).
    public static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ai.octomil.mlx-models", isDirectory: true)
    }()

    /// GPU memory cache limit in bytes. Default: 2 GB.
    public var gpuCacheLimit: Int

    private var loadedContainers: [String: ModelContainer] = [:]

    public init(gpuCacheLimit: Int = 2 * 1024 * 1024 * 1024) {
        self.gpuCacheLimit = gpuCacheLimit
    }

    /// Load an MLX model from a local directory containing config.json and safetensors.
    /// - Parameter url: Local directory URL.
    /// - Returns: A loaded ``ModelContainer``.
    public func loadModel(from url: URL) async throws -> ModelContainer {
        let key = url.absoluteString
        if let cached = loadedContainers[key] {
            return cached
        }

        MLX.GPU.set(cacheLimit: gpuCacheLimit)

        let configuration = ModelConfiguration(directory: url)
        let container = try await MLXLMCommon.loadModelContainer(configuration: configuration)

        loadedContainers[key] = container
        return container
    }

    /// Load an MLX model from HuggingFace Hub (for development/testing).
    /// - Parameter modelId: HuggingFace model ID (e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit").
    /// - Returns: A loaded ``ModelContainer``.
    public func loadFromHub(modelId: String) async throws -> ModelContainer {
        if let cached = loadedContainers[modelId] {
            return cached
        }

        MLX.GPU.set(cacheLimit: gpuCacheLimit)

        let configuration = ModelConfiguration(id: modelId)
        let container = try await MLXLMCommon.loadModelContainer(configuration: configuration)

        loadedContainers[modelId] = container
        return container
    }

    /// Evict a specific model from the in-memory cache.
    public func evict(key: String) {
        loadedContainers.removeValue(forKey: key)
    }

    /// Evict all cached models.
    public func evictAll() {
        loadedContainers.removeAll()
    }

    /// Ensure the cache directory exists on disk, migrating from old Caches location if needed.
    public static func ensureCacheDirectory() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Migrate from old Caches location
        let oldDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ai.octomil.mlx-models", isDirectory: true)
        guard fm.fileExists(atPath: oldDir.path),
              let contents = try? fm.contentsOfDirectory(atPath: oldDir.path),
              !contents.isEmpty else { return }
        for item in contents {
            let source = oldDir.appendingPathComponent(item)
            let dest = cacheDirectory.appendingPathComponent(item)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.moveItem(at: source, to: dest)
            } else {
                try? fm.removeItem(at: source)
            }
        }
        try? fm.removeItem(at: oldDir)
    }

    /// Get the cache path for a given model ID and version.
    public static func cachePath(modelId: String, version: String) -> URL {
        let sanitized = modelId.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory
            .appendingPathComponent(sanitized, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }
}

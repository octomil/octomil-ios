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

    /// Cache directory for MLX models.
    public static let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("ai.octomil.mlx-models", isDirectory: true)
    }()

    /// GPU memory cache limit in bytes. Default: 512 MB for iOS.
    public var gpuCacheLimit: Int

    private var loadedContainers: [String: ModelContainer] = [:]

    public init(gpuCacheLimit: Int = 512 * 1024 * 1024) {
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

    /// Ensure the cache directory exists on disk.
    public static func ensureCacheDirectory() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Get the cache path for a given model ID and version.
    public static func cachePath(modelId: String, version: String) -> URL {
        let sanitized = modelId.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory
            .appendingPathComponent(sanitized, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }
}

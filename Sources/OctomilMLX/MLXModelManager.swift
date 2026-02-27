import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil

/// Manages server-driven MLX model downloads.
///
/// Wraps ``APIClient`` to request `format: "mlx"` models from the server,
/// downloads and extracts model archives, then loads into ``ModelContainer``.
@available(iOS 17.0, macOS 14.0, *)
public actor MLXModelManager {

    private let apiClient: APIClient
    private let loader: MLXModelLoader
    private let fileManager = FileManager.default
    private var downloadTasks: [String: Task<MLXDeployedModel, Error>] = [:]

    /// Creates an MLX model manager.
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - gpuCacheLimit: GPU memory cache limit in bytes (default: 512 MB).
    public init(apiClient: APIClient, gpuCacheLimit: Int = 512 * 1024 * 1024) {
        self.apiClient = apiClient
        self.loader = MLXModelLoader(gpuCacheLimit: gpuCacheLimit)
    }

    /// Download an MLX model from the server and load it.
    ///
    /// Deduplicates in-flight downloads for the same model+version.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    /// - Returns: A deployed MLX model ready for inference.
    public func downloadModel(modelId: String, version: String) async throws -> MLXDeployedModel {
        let cacheKey = "\(modelId)_\(version)"

        if let existingTask = downloadTasks[cacheKey] {
            return try await existingTask.value
        }

        // Check if already cached on disk
        let cachePath = MLXModelLoader.cachePath(modelId: modelId, version: version)
        if fileManager.fileExists(atPath: cachePath.appendingPathComponent("config.json").path) {
            let container = try await loader.loadModel(from: cachePath)
            return MLXDeployedModel(name: modelId, modelContainer: container)
        }

        let task = Task<MLXDeployedModel, Error> {
            defer {
                Task { await self.removeDownloadTask(cacheKey) }
            }

            let downloadInfo = try await apiClient.getDownloadURL(
                modelId: modelId,
                version: version,
                format: "mlx"
            )

            guard let downloadURL = URL(string: downloadInfo.url) else {
                throw OctomilError.invalidRequest(reason: "Invalid download URL")
            }

            let archiveData = try await apiClient.downloadData(from: downloadURL)

            // Ensure cache directory exists
            try MLXModelLoader.ensureCacheDirectory()
            let modelDir = MLXModelLoader.cachePath(modelId: modelId, version: version)
            try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

            // Write archive and extract
            let archivePath = modelDir.appendingPathComponent("model.zip")
            try archiveData.write(to: archivePath)
            try extractArchive(at: archivePath, to: modelDir)
            try? fileManager.removeItem(at: archivePath)

            // Load the model
            let container = try await loader.loadModel(from: modelDir)
            return MLXDeployedModel(name: modelId, modelContainer: container)
        }

        downloadTasks[cacheKey] = task
        return try await task.value
    }

    private func removeDownloadTask(_ key: String) {
        downloadTasks.removeValue(forKey: key)
    }

    /// Extract a zip archive to a destination directory.
    private func extractArchive(at archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", archiveURL.path, destination.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw OctomilError.modelCompilationFailed(reason: "Failed to extract MLX model archive")
        }
    }
}

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil

/// Manages server-driven MLX model downloads.
///
/// Wraps ``APIClient`` to request models from the server using a server-fetched
/// format preference, downloads and extracts model archives, then loads into
/// ``ModelContainer``.
@available(iOS 17.0, macOS 14.0, *)
public actor MLXModelManager {

    private let apiClient: APIClient
    private let deviceMetadata = DeviceMetadata()
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

            // Resolve the best format for this device from capability payload.
            let resolution = try await apiClient.resolveModelFormat(
                modelId: modelId,
                version: version,
                capabilities: ModelResolveRequest(
                    platform: "ios",
                    model: self.deviceMetadata.model,
                    manufacturer: self.deviceMetadata.manufacturer,
                    cpuArchitecture: self.deviceMetadata.cpuArchitecture,
                    osVersion: self.deviceMetadata.osVersion,
                    totalMemoryMb: self.deviceMetadata.totalMemoryMB,
                    gpuAvailable: self.deviceMetadata.gpuAvailable,
                    npuAvailable: self.deviceMetadata.gpuAvailable,
                    supportedRuntimes: ["mlx", "coreml"],
                    computeUnits: "all"
                )
            )

            let downloadInfo = try await apiClient.getDownloadURL(
                modelId: modelId,
                version: resolution.version,
                format: resolution.format
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
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", archiveURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OctomilError.modelCompilationFailed(reason: "Failed to extract MLX model archive")
        }
        #else
        throw OctomilError.modelCompilationFailed(
            reason: "MLX model archive extraction requires macOS (Process is unavailable on iOS)"
        )
        #endif
    }
}

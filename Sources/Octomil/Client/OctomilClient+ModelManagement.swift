import Foundation

// MARK: - Model Management

extension OctomilClient {

    /// Downloads a model from the server.
    ///
    /// The model is cached locally after download for offline use.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to download.
    ///   - version: Optional specific version. If nil, downloads the latest version.
    /// - Returns: The downloaded model ready for inference.
    /// - Throws: `OctomilError` if download fails.
    public func downloadModel(
        modelId: String,
        version: String? = nil
    ) async throws -> OctomilModel {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Downloading model: \(modelId)")
        }

        // Resolve version if not specified
        let resolvedVersion: String
        if let version = version {
            resolvedVersion = version
        } else {
            let resolution = try await apiClient.resolveVersion(deviceId: deviceId, modelId: modelId)
            resolvedVersion = resolution.version
        }

        return try await modelManager.downloadModel(modelId: modelId, version: resolvedVersion)
    }

    /// Gets a cached model without network access.
    ///
    /// - Parameter modelId: Identifier of the model.
    /// - Returns: The cached model, or nil if not cached.
    public func getCachedModel(modelId: String) -> OctomilModel? {
        return modelManager.getCachedModel(modelId: modelId)
    }

    /// Gets a cached model with a specific version.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model.
    ///   - version: Version of the model.
    /// - Returns: The cached model, or nil if not cached.
    public func getCachedModel(modelId: String, version: String) -> OctomilModel? {
        return modelManager.getCachedModel(modelId: modelId, version: version)
    }

    /// Checks if a model update is available.
    ///
    /// - Parameter modelId: Identifier of the model.
    /// - Returns: Update information if available, nil otherwise.
    /// - Throws: `OctomilError` if the check fails.
    public func checkForUpdates(modelId: String) async throws -> ModelUpdateInfo? {
        guard let cachedModel = getCachedModel(modelId: modelId) else {
            return nil
        }

        return try await apiClient.checkForUpdates(
            modelId: modelId,
            currentVersion: cachedModel.version
        )
    }

    /// Clears all cached models.
    public func clearCache() async throws {
        try await modelManager.clearCache()

        if configuration.enableLogging {
            logger.info("Model cache cleared")
        }
    }
}

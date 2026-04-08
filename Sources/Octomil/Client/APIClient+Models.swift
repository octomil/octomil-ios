import Foundation

// MARK: - Model Endpoints

extension APIClient {

    /// Gets the resolved version for a device and model.
    /// - Parameters:
    ///   - deviceId: Device identifier.
    ///   - modelId: Model identifier.
    /// - Returns: Version resolution response.
    public func resolveVersion(deviceId: String, modelId: String) async throws -> VersionResolutionResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/version"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "include_bucket", value: "true")
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Resolve optimal model format for the current device capabilities.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    ///   - capabilities: Device capability payload.
    /// - Returns: Resolved model format and download metadata.
    public func resolveModelFormat(
        modelId: String,
        version: String,
        capabilities: ModelResolveRequest
    ) async throws -> ModelResolveResponse {
        let url = serverURL.appendingPathComponent("api/v1/models/\(modelId)/versions/\(version)/resolve")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(capabilities)
        return try await performRequest(urlRequest)
    }

    /// Gets model metadata.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Optional specific version.
    /// - Returns: Model metadata.
    public func getModelMetadata(modelId: String, version: String? = nil) async throws -> ModelMetadata {
        var path = "api/v1/models/\(modelId)/versions"
        if let version = version {
            path += "/\(version)"
        } else {
            path += "/\(Self.defaultVersionAlias)"
        }

        var urlRequest = URLRequest(url: serverURL.appendingPathComponent(path))
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let response: ModelVersionResponse = try await performRequest(urlRequest)
        return ModelMetadata(
            modelId: response.modelId,
            version: response.version,
            checksum: response.checksum,
            fileSize: response.sizeBytes,
            createdAt: response.createdAt,
            format: response.format,
            supportsTraining: true,
            description: response.description,
            inputSchema: nil,
            outputSchema: nil,
            serverContract: response.modelContract
        )
    }

    /// Gets a pre-signed download URL for a model.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    ///   - format: Model format. Defaults to "auto" (server resolves best format).
    /// - Returns: Download URL response.
    public func getDownloadURL(modelId: String, version: String, format: String = "auto") async throws -> DownloadURLResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/models/\(modelId)/versions/\(version)/download-url"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: format)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets the device-specific MNN runtime config for optimized inference.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - deviceType: Device profile key (e.g. "iphone_15_pro").
    /// - Returns: MNN config dictionary.
    public func getDeviceConfig(modelId: String, deviceType: String) async throws -> [String: Any] {
        let url = serverURL.appendingPathComponent("api/v1/models/\(modelId)/optimized-config/\(deviceType)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctomilError.unknown(underlying: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OctomilError.serverError(statusCode: httpResponse.statusCode, message: "No optimized config")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OctomilError.decodingError(underlying: "Invalid MNN config response")
        }

        return json
    }

    /// Checks for model updates.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - currentVersion: Current version on device.
    /// - Returns: Update info if available, nil otherwise.
    public func checkForUpdates(modelId: String, currentVersion: String) async throws -> ModelUpdateInfo? {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/models/\(modelId)/updates"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "current_version", value: currentVersion)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        do {
            return try await performRequest(urlRequest)
        } catch OctomilError.serverError(let statusCode, _) where statusCode == 404 {
            // No update available
            return nil
        }
    }

    /// Gets model metadata by ID.
    /// - Parameter modelId: Model identifier.
    /// - Returns: Model response with metadata.
    public func getModel(modelId: String) async throws -> ModelResponse {
        let url = serverURL.appendingPathComponent("api/v1/models/\(modelId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Checks server health.
    /// - Returns: Health response with status.
    public func healthCheck() async throws -> HealthResponse {
        let url = serverURL.appendingPathComponent("health")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        // Health check does not require auth
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        return try await performRequest(urlRequest)
    }
}

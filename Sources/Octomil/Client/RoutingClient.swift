import Foundation
import os.log

// MARK: - Routing Models

/// Device capabilities sent to the routing API.
public struct RoutingDeviceCapabilities: Codable, Sendable {
    public let platform: String
    public let model: String
    public let totalMemoryMb: Int
    public let gpuAvailable: Bool
    public let npuAvailable: Bool
    public let supportedRuntimes: [String]

    enum CodingKeys: String, CodingKey {
        case platform
        case model
        case totalMemoryMb = "total_memory_mb"
        case gpuAvailable = "gpu_available"
        case npuAvailable = "npu_available"
        case supportedRuntimes = "supported_runtimes"
    }
}

/// Request body for POST /api/v1/route.
struct RoutingRequest: Codable {
    let modelId: String
    let modelParams: Int
    let modelSizeMb: Double
    let deviceCapabilities: RoutingDeviceCapabilities
    let prefer: String

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case modelParams = "model_params"
        case modelSizeMb = "model_size_mb"
        case deviceCapabilities = "device_capabilities"
        case prefer
    }
}

/// Fallback target from routing response.
public struct RoutingFallbackTarget: Codable, Sendable {
    public let endpoint: String
}

/// Response from POST /api/v1/route.
public struct RoutingDecision: Codable, Sendable {
    public let id: String
    public let target: String
    public let format: String
    public let engine: String
    public let fallbackTarget: RoutingFallbackTarget?

    enum CodingKeys: String, CodingKey {
        case id, target, format, engine
        case fallbackTarget = "fallback_target"
    }
}

/// Request body for POST /api/v1/inference.
struct CloudInferenceRequest: Encodable {
    let modelId: String
    let inputData: [String: AnyCodable]
    let parameters: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case inputData = "input_data"
        case parameters
    }
}

/// Response from POST /api/v1/inference.
public struct CloudInferenceResponse: Codable, Sendable {
    public let output: AnyCodable
    public let latencyMs: Double
    public let provider: String

    enum CodingKeys: String, CodingKey {
        case output
        case latencyMs = "latency_ms"
        case provider
    }
}

/// Routing preference for execution target.
public enum RoutingPreference: String, Sendable {
    case device
    case cloud
    case cheapest
    case fastest
}

/// Configuration for the routing client.
public struct RoutingConfig: Sendable {
    public let serverURL: URL
    public let apiKey: String
    public let cacheTtlSeconds: TimeInterval
    public let prefer: RoutingPreference
    public let modelParams: Int
    public let modelSizeMb: Double

    public init(
        serverURL: URL,
        apiKey: String,
        cacheTtlSeconds: TimeInterval = 300,
        prefer: RoutingPreference = .fastest,
        modelParams: Int = 0,
        modelSizeMb: Double = 0
    ) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.cacheTtlSeconds = cacheTtlSeconds
        self.prefer = prefer
        self.modelParams = modelParams
        self.modelSizeMb = modelSizeMb
    }
}

// MARK: - RoutingClient

/// Calls the Octomil routing API to decide whether inference should run
/// on-device or in the cloud. Caches decisions with a configurable TTL.
public actor RoutingClient {

    // MARK: - Properties

    private let config: RoutingConfig
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger

    private var cache: [String: CacheEntry] = [:]

    private struct CacheEntry {
        let decision: RoutingDecision
        let expiresAt: Date
    }

    // MARK: - Initialization

    public init(config: RoutingConfig) {
        self.config = config
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "RoutingClient")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: sessionConfig)

        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Ask the routing API whether to run on-device or in the cloud.
    ///
    /// Returns a cached decision when available and not expired.
    /// Returns `nil` on any failure so the caller can fall back to local inference.
    public func route(
        modelId: String,
        deviceCapabilities: RoutingDeviceCapabilities
    ) async -> RoutingDecision? {
        if let cached = cache[modelId], cached.expiresAt > Date() {
            return cached.decision
        }

        let body = RoutingRequest(
            modelId: modelId,
            modelParams: config.modelParams,
            modelSizeMb: config.modelSizeMb,
            deviceCapabilities: deviceCapabilities,
            prefer: config.prefer.rawValue
        )

        let url = config.serverURL.appendingPathComponent("api/v1/route")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try jsonEncoder.encode(body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.warning("Routing API returned non-200, falling back to device")
                return nil
            }

            let decision = try jsonDecoder.decode(RoutingDecision.self, from: data)

            cache[modelId] = CacheEntry(
                decision: decision,
                expiresAt: Date().addingTimeInterval(config.cacheTtlSeconds)
            )

            return decision
        } catch {
            logger.warning("Routing request failed: \(error.localizedDescription), falling back to device")
            return nil
        }
    }

    /// Run inference in the cloud via POST /api/v1/inference.
    ///
    /// Throws on failure so the caller can catch and fall back to local inference.
    public func cloudInfer(
        modelId: String,
        inputData: [String: Any],
        parameters: [String: Any] = [:]
    ) async throws -> CloudInferenceResponse {
        let body = CloudInferenceRequest(
            modelId: modelId,
            inputData: inputData.mapValues { AnyCodable($0) },
            parameters: parameters.mapValues { AnyCodable($0) }
        )

        let url = config.serverURL.appendingPathComponent("api/v1/inference")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try jsonEncoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OctomilError.serverError(
                statusCode: statusCode,
                message: "Cloud inference failed"
            )
        }

        return try jsonDecoder.decode(CloudInferenceResponse.self, from: data)
    }

    /// Invalidate all cached routing decisions.
    public func clearCache() {
        cache.removeAll()
    }

    /// Invalidate the cached routing decision for a specific model.
    public func invalidate(modelId: String) {
        cache.removeValue(forKey: modelId)
    }
}

// MARK: - Device Capabilities Helper

extension DeviceMetadata {
    /// Build routing device capabilities from the current device info.
    public func routingCapabilities() -> RoutingDeviceCapabilities {
        var runtimes = ["coreml"]
        if gpuAvailable {
            runtimes.append("metal")
        }

        return RoutingDeviceCapabilities(
            platform: platform,
            model: model,
            totalMemoryMb: totalMemoryMB ?? 0,
            gpuAvailable: gpuAvailable,
            npuAvailable: gpuAvailable, // Neural Engine is detected via same flag
            supportedRuntimes: runtimes
        )
    }
}

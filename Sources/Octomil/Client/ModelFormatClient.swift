import Foundation
import os.log

// MARK: - Model Format Response

/// Server-recommended model format for a given model and platform.
///
/// Fetched from `GET /api/v1/models/{modelId}/format?platform=ios` and cached
/// both in-memory and on disk.
public struct ModelFormatPreference: Codable, Sendable {
    /// Preferred model format (e.g. "coreml", "mlx", "onnx", "auto").
    public let format: String
    /// Optional secondary format to try on failure.
    public let fallbackFormat: String?
    /// Time-to-live in seconds before the preference should be refreshed.
    public let ttlSeconds: Int
    /// Timestamp when this preference was fetched (filled client-side).
    public var fetchedAt: TimeInterval
    /// ETag for conditional requests (filled client-side).
    public var etag: String

    enum CodingKeys: String, CodingKey {
        case format
        case fallbackFormat = "fallback_format"
        case ttlSeconds = "ttl_seconds"
        case fetchedAt = "fetched_at"
        case etag
    }
}

// MARK: - Default Fallback

/// Minimal fallback preference used when the server is unreachable and no cache exists.
/// Returns "auto" to let the runtime figure out the best format without revealing
/// a hardcoded preference.
let defaultModelFormatPreference = ModelFormatPreference(
    format: "auto",
    fallbackFormat: nil,
    ttlSeconds: 0,
    fetchedAt: 0,
    etag: ""
)

// MARK: - ModelFormatClient

/// Fetches and caches the server-recommended model format from
/// `GET /api/v1/models/{modelId}/format?platform=ios`.
///
/// Format preference is cached to disk and refreshed using ETag-based conditional
/// requests. Falls back to disk cache on error, then to "auto".
///
/// Follows the same pattern as ``PolicyClient``:
/// - Actor-based for thread safety
/// - URLSession for HTTP
/// - JSONEncoder/JSONDecoder for serialization
/// - Disk cache with atomic writes
/// - ETag-based conditional requests
/// - Fallback to minimal default
public actor ModelFormatClient {

    private let apiBase: URL
    private let apiKey: String?
    private let platform: String
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger
    private let cacheDirectory: URL

    /// In-memory cache keyed by model ID.
    private var inMemoryCache: [String: ModelFormatPreference] = [:]

    public init(apiBase: URL, apiKey: String?, platform: String = "ios") {
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.platform = platform
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelFormatClient")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: sessionConfig)

        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("ai.octomil.model-format", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Internal init for testing with a custom URLSession.
    init(apiBase: URL, apiKey: String?, platform: String = "ios", session: URLSession) {
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.platform = platform
        self.session = session
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelFormatClient")
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("ai.octomil.model-format", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Returns the server-recommended format for a model, refreshing if expired.
    ///
    /// Resolution order: in-memory (if fresh) -> server fetch -> disk cache -> default ("auto").
    public func getPreferredFormat(modelId: String) async -> ModelFormatPreference {
        // Return in-memory preference if still within TTL.
        if let cached = inMemoryCache[modelId], !isExpired(cached) {
            return cached
        }

        // Try fetching from server.
        let currentEtag = inMemoryCache[modelId]?.etag ?? loadFromDisk(modelId: modelId)?.etag ?? ""
        if let fetched = await fetchFromServer(modelId: modelId, etag: currentEtag) {
            inMemoryCache[modelId] = fetched
            persistToDisk(modelId: modelId, preference: fetched)
            return fetched
        }

        // Server unavailable — use in-memory (even if expired) or disk cache.
        if let cached = inMemoryCache[modelId] {
            logger.info("Using expired in-memory format preference for \(modelId) (server unreachable)")
            return cached
        }
        if let disk = loadFromDisk(modelId: modelId) {
            logger.info("Using disk-cached format preference for \(modelId) (server unreachable)")
            inMemoryCache[modelId] = disk
            return disk
        }

        // No cache at all — embedded default.
        logger.info("No cached format preference for \(modelId), using default (auto)")
        return defaultModelFormatPreference
    }

    /// Convenience to get just the format string for a model.
    public func getFormat(modelId: String) async -> String {
        let preference = await getPreferredFormat(modelId: modelId)
        return preference.format
    }

    /// Force-clear all cached format preference data.
    public func clearCache() {
        inMemoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Clear cached format preference for a specific model.
    public func clearCache(modelId: String) {
        inMemoryCache.removeValue(forKey: modelId)
        let fileURL = cacheFileURL(modelId: modelId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Network

    private func fetchFromServer(modelId: String, etag: String) async -> ModelFormatPreference? {
        var components = URLComponents(
            url: apiBase.appendingPathComponent("api/v1/models/\(modelId)/format"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "platform", value: platform)
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            // 304 Not Modified — current cache is still valid, refresh fetchedAt.
            if httpResponse.statusCode == 304 {
                if var current = inMemoryCache[modelId] {
                    current.fetchedAt = Date().timeIntervalSince1970
                    return current
                }
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning("Format API returned \(httpResponse.statusCode) for \(modelId)")
                return nil
            }

            var preference = try jsonDecoder.decode(ModelFormatPreference.self, from: data)
            preference.fetchedAt = Date().timeIntervalSince1970
            preference.etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? ""
            return preference
        } catch {
            logger.warning("Format fetch failed for \(modelId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Disk Cache

    private func cacheFileURL(modelId: String) -> URL {
        // Sanitize modelId for use as filename
        let safe = modelId.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("format_\(safe).json")
    }

    private func persistToDisk(modelId: String, preference: ModelFormatPreference) {
        do {
            let data = try jsonEncoder.encode(preference)
            try data.write(to: cacheFileURL(modelId: modelId), options: .atomic)
        } catch {
            logger.warning("Failed to persist format preference for \(modelId): \(error.localizedDescription)")
        }
    }

    private func loadFromDisk(modelId: String) -> ModelFormatPreference? {
        let fileURL = cacheFileURL(modelId: modelId)
        guard let data = try? Data(contentsOf: fileURL),
              let preference = try? jsonDecoder.decode(ModelFormatPreference.self, from: data) else {
            return nil
        }
        return preference
    }

    // MARK: - Helpers

    private func isExpired(_ preference: ModelFormatPreference) -> Bool {
        let age = Date().timeIntervalSince1970 - preference.fetchedAt
        return age > Double(preference.ttlSeconds)
    }
}

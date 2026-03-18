import Foundation
import os.log

// MARK: - Device Profile Response

/// Server-provided device profile mapping for a given machine identifier.
///
/// Fetched from `GET /api/v1/devices/profiles` and cached both in-memory
/// and on disk with ETag-based conditional requests.
public struct DeviceProfileMapping: Codable, Sendable {
    /// Map of machine identifier (e.g. "iPhone16,1") to profile tier (e.g. "iphone_15_pro").
    public let profiles: [String: String]
    /// Time-to-live in seconds before the mapping should be refreshed.
    public let ttlSeconds: Int
    /// Timestamp when this mapping was fetched (filled client-side).
    public var fetchedAt: TimeInterval
    /// ETag for conditional requests (filled client-side).
    public var etag: String

    enum CodingKeys: String, CodingKey {
        case profiles
        case ttlSeconds = "ttl_seconds"
        case fetchedAt = "fetched_at"
        case etag
    }
}

// MARK: - RAM-Based Fallback Tier

/// Fallback device tier classification based on available RAM when the server
/// is unreachable and no cached mapping exists. Avoids hardcoding any specific
/// device model identifiers.
public enum DeviceRAMTier: String, Sendable {
    /// 8 GB+ RAM (e.g. Pro devices with A17 Pro / A18 Pro)
    case high = "high"
    /// 4-7 GB RAM (e.g. standard iPhone 14/15/16)
    case mid = "mid"
    /// < 4 GB RAM (older devices)
    case low = "low"

    /// Classify based on total physical memory in megabytes.
    static func classify(totalMemoryMB: Int) -> DeviceRAMTier {
        if totalMemoryMB >= 8 * 1024 {
            return .high
        } else if totalMemoryMB >= 4 * 1024 {
            return .mid
        } else {
            return .low
        }
    }
}

// MARK: - DeviceProfileClient

/// Fetches and caches server-provided device-to-profile mappings from
/// `GET /api/v1/devices/profiles`.
///
/// When the server is unreachable and no cache exists, falls back to a
/// RAM-based tier classification (high/mid/low) with no hardcoded device
/// model identifiers.
///
/// Follows the same pattern as ``ModelFormatClient``:
/// - Actor-based for thread safety
/// - URLSession for HTTP
/// - JSONEncoder/JSONDecoder for serialization
/// - Disk cache with atomic writes
/// - ETag-based conditional requests
/// - Fallback to RAM-based classification
public actor DeviceProfileClient {

    private let apiBase: URL
    private let apiKey: String?
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger
    private let cacheDirectory: URL

    /// In-memory cache of the mapping.
    private var inMemoryCache: DeviceProfileMapping?

    public init(apiBase: URL, apiKey: String?) {
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "DeviceProfileClient")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: sessionConfig)

        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("ai.octomil.device-profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Internal init for testing with a custom URLSession.
    init(apiBase: URL, apiKey: String?, session: URLSession) {
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.session = session
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "DeviceProfileClient")
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("ai.octomil.device-profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Resolves a device profile key for the given machine identifier.
    ///
    /// Resolution order:
    /// 1. In-memory cache (if fresh) -> look up machineId
    /// 2. Server fetch -> look up machineId
    /// 3. Disk cache -> look up machineId
    /// 4. RAM-based fallback tier (no hardcoded device IDs)
    ///
    /// - Parameters:
    ///   - machineId: The machine identifier (e.g. "iPhone16,1").
    ///   - totalMemoryMB: Total physical memory in megabytes for RAM-based fallback.
    /// - Returns: A device profile key string.
    public func resolveProfile(machineId: String, totalMemoryMB: Int) async -> String {
        let mapping = await getMapping()

        // Look up the machine ID in the mapping (case-insensitive).
        let normalizedId = machineId.lowercased()
        for (key, value) in mapping.profiles {
            if key.lowercased() == normalizedId {
                return value
            }
        }

        // Machine ID not in mapping -- classify by RAM.
        let tier = DeviceRAMTier.classify(totalMemoryMB: totalMemoryMB)
        logger.info("Machine \(machineId) not in server profiles, falling back to RAM tier: \(tier.rawValue)")
        return tier.rawValue
    }

    /// Returns the full device profile mapping, refreshing from server if expired.
    ///
    /// Resolution order: in-memory (if fresh) -> server fetch -> disk cache -> empty mapping.
    public func getMapping() async -> DeviceProfileMapping {
        // Return in-memory mapping if still within TTL.
        if let cached = inMemoryCache, !isExpired(cached) {
            return cached
        }

        // Try fetching from server.
        let currentEtag = inMemoryCache?.etag ?? loadFromDisk()?.etag ?? ""
        if let fetched = await fetchFromServer(etag: currentEtag) {
            inMemoryCache = fetched
            persistToDisk(mapping: fetched)
            return fetched
        }

        // Server unavailable -- use in-memory (even if expired) or disk cache.
        if let cached = inMemoryCache {
            logger.info("Using expired in-memory device profiles (server unreachable)")
            return cached
        }
        if let disk = loadFromDisk() {
            logger.info("Using disk-cached device profiles (server unreachable)")
            inMemoryCache = disk
            return disk
        }

        // No cache at all -- return empty mapping (caller will use RAM fallback).
        logger.info("No cached device profiles, RAM-based fallback will be used")
        return DeviceProfileMapping(profiles: [:], ttlSeconds: 0, fetchedAt: 0, etag: "")
    }

    /// Force-clear all cached profile data.
    public func clearCache() {
        inMemoryCache = nil
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Network

    private func fetchFromServer(etag: String) async -> DeviceProfileMapping? {
        let url = apiBase.appendingPathComponent("api/v1/devices/profiles")

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

            // 304 Not Modified -- current cache is still valid, refresh fetchedAt.
            if httpResponse.statusCode == 304 {
                if var current = inMemoryCache {
                    current.fetchedAt = Date().timeIntervalSince1970
                    return current
                }
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning("Device profiles API returned \(httpResponse.statusCode)")
                return nil
            }

            var mapping = try jsonDecoder.decode(DeviceProfileMapping.self, from: data)
            mapping.fetchedAt = Date().timeIntervalSince1970
            mapping.etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? ""
            return mapping
        } catch {
            logger.warning("Device profiles fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Disk Cache

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent("device_profiles.json")
    }

    private func persistToDisk(mapping: DeviceProfileMapping) {
        do {
            let data = try jsonEncoder.encode(mapping)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist device profiles: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() -> DeviceProfileMapping? {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let mapping = try? jsonDecoder.decode(DeviceProfileMapping.self, from: data) else {
            return nil
        }
        return mapping
    }

    // MARK: - Helpers

    private func isExpired(_ mapping: DeviceProfileMapping) -> Bool {
        let age = Date().timeIntervalSince1970 - mapping.fetchedAt
        return age > Double(mapping.ttlSeconds)
    }
}

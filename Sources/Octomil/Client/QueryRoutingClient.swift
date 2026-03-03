import Foundation
import os.log

// MARK: - Query Routing Models

/// Routing policy fetched from the server and cached locally.
public struct RoutingPolicy: Codable, Sendable {
    public let version: Int
    public let thresholds: Thresholds
    public let complexIndicators: [String]
    public let deterministicEnabled: Bool
    public let ttlSeconds: Int
    public var fetchedAt: TimeInterval
    public var etag: String

    public struct Thresholds: Codable, Sendable {
        public let fastMaxWords: Int
        public let qualityMinWords: Int

        enum CodingKeys: String, CodingKey {
            case fastMaxWords = "fast_max_words"
            case qualityMinWords = "quality_min_words"
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case thresholds
        case complexIndicators = "complex_indicators"
        case deterministicEnabled = "deterministic_enabled"
        case ttlSeconds = "ttl_seconds"
        case fetchedAt = "fetched_at"
        case etag
    }
}

/// Information about an available model for routing decisions.
public struct QueryModelInfo: Sendable {
    public let name: String
    public let tier: String  // "fast", "balanced", "quality"
    public let paramB: Double
    public let loaded: Bool

    public init(name: String, tier: String, paramB: Double, loaded: Bool) {
        self.name = name
        self.tier = tier
        self.paramB = paramB
        self.loaded = loaded
    }
}

/// Result of routing a query to a model tier.
public struct QueryRoutingDecision: Sendable {
    public let modelName: String
    public let complexityScore: Double
    public let tier: String
    public let strategy: String
    public let fallbackChain: [String]
    public let deterministicResult: DeterministicResult?
}

/// Result from deterministic evaluation (e.g. pure arithmetic).
public struct DeterministicResult: Sendable {
    public let answer: String
    public let method: String
    public let confidence: Double
}

// MARK: - Default Policy

/// Embedded default policy matching the server-side defaults.
/// Used on first launch before any server fetch succeeds.
let defaultRoutingPolicy = RoutingPolicy(
    version: 1,
    thresholds: RoutingPolicy.Thresholds(fastMaxWords: 10, qualityMinWords: 50),
    complexIndicators: [
        "code", "explain", "compare", "analyze", "implement",
        "algorithm", "step by step", "debug", "optimize", "refactor",
        "architecture", "design pattern", "trade-off", "proof"
    ],
    deterministicEnabled: true,
    ttlSeconds: 300,
    fetchedAt: 0,
    etag: ""
)

// MARK: - PolicyClient

/// Fetches and caches the routing policy from GET /api/v1/route/policy.
///
/// Policy is cached to disk and refreshed using ETag-based conditional requests.
/// Falls back to disk cache on error, then to an embedded default.
public actor PolicyClient {

    private let apiBase: URL
    private let apiKey: String?
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger
    private let cacheURL: URL

    private var inMemoryPolicy: RoutingPolicy?

    public init(apiBase: URL, apiKey: String?) {
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PolicyClient")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: sessionConfig)

        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheURL = cacheDir.appendingPathComponent("octomil_routing_policy.json")
    }

    /// Internal init for testing with a custom URLSession.
    init(apiBase: URL, apiKey: String?, session: URLSession) {
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.session = session
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "PolicyClient")
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheURL = cacheDir.appendingPathComponent("octomil_routing_policy.json")
    }

    // MARK: - Public API

    /// Returns the current routing policy, refreshing from the server if expired.
    ///
    /// Resolution order: in-memory (if fresh) -> server fetch -> disk cache -> default.
    public func getPolicy() async -> RoutingPolicy {
        // Return in-memory policy if still within TTL.
        if let cached = inMemoryPolicy, !isExpired(cached) {
            return cached
        }

        // Try fetching from server.
        let currentEtag = inMemoryPolicy?.etag ?? loadFromDisk()?.etag ?? ""
        if let fetched = await fetchFromServer(etag: currentEtag) {
            inMemoryPolicy = fetched
            persistToDisk(fetched)
            return fetched
        }

        // Server unavailable — use in-memory (even if expired) or disk cache.
        if let cached = inMemoryPolicy {
            logger.info("Using expired in-memory policy (server unreachable)")
            return cached
        }
        if let disk = loadFromDisk() {
            logger.info("Using disk-cached policy (server unreachable)")
            inMemoryPolicy = disk
            return disk
        }

        // No cache at all — embedded default.
        logger.info("No cached policy available, using embedded default")
        return defaultRoutingPolicy
    }

    /// Force-clear all cached policy data.
    public func clearCache() {
        inMemoryPolicy = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Network

    private func fetchFromServer(etag: String) async -> RoutingPolicy? {
        let url = apiBase.appendingPathComponent("api/v1/route/policy")
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
                if var current = inMemoryPolicy {
                    current.fetchedAt = Date().timeIntervalSince1970
                    return current
                }
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning("Policy API returned \(httpResponse.statusCode)")
                return nil
            }

            var policy = try jsonDecoder.decode(RoutingPolicy.self, from: data)
            policy.fetchedAt = Date().timeIntervalSince1970
            policy.etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? ""
            return policy
        } catch {
            logger.warning("Policy fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Disk Cache

    private func persistToDisk(_ policy: RoutingPolicy) {
        do {
            let data = try jsonEncoder.encode(policy)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist routing policy: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() -> RoutingPolicy? {
        guard let data = try? Data(contentsOf: cacheURL),
              let policy = try? jsonDecoder.decode(RoutingPolicy.self, from: data) else {
            return nil
        }
        return policy
    }

    // MARK: - Helpers

    private func isExpired(_ policy: RoutingPolicy) -> Bool {
        let age = Date().timeIntervalSince1970 - policy.fetchedAt
        return age > Double(policy.ttlSeconds)
    }
}

// MARK: - QueryRouter

/// Routes queries to model tiers using the cached routing policy.
///
/// Applies local heuristics (word count + complex indicator matching) for
/// offline-capable routing. Falls back to the server policy thresholds.
public actor QueryRouter {

    private let models: [String: QueryModelInfo]
    private let policyClient: PolicyClient?
    private let enableDeterministic: Bool
    private let logger: Logger

    /// Regex for pure arithmetic expressions (e.g. "what is 2+3", "calculate 100/5").
    private static let arithmeticPattern = try! NSRegularExpression(
        pattern: #"^(what is |calculate |compute |eval )?\d+(\.\d+)?\s*[+\-*/^%]\s*\d+(\.\d+)?(\s*[+\-*/^%]\s*\d+(\.\d+)?)*\s*\??$"#,
        options: [.caseInsensitive]
    )

    /// Tier priority for fallback ordering.
    private static let tierPriority = ["fast", "balanced", "quality"]

    /// - Parameters:
    ///   - models: Available models keyed by name.
    ///   - apiBase: Server URL for policy fetching. `nil` disables server fetch.
    ///   - apiKey: Optional API key for authenticated policy requests.
    ///   - enableDeterministic: Whether to intercept pure arithmetic queries.
    public init(
        models: [String: QueryModelInfo],
        apiBase: URL? = nil,
        apiKey: String? = nil,
        enableDeterministic: Bool = true
    ) {
        self.models = models
        self.enableDeterministic = enableDeterministic
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "QueryRouter")

        if let apiBase {
            self.policyClient = PolicyClient(apiBase: apiBase, apiKey: apiKey)
        } else {
            self.policyClient = nil
        }
    }

    /// Internal init for testing with a pre-built PolicyClient.
    init(
        models: [String: QueryModelInfo],
        policyClient: PolicyClient?,
        enableDeterministic: Bool = true
    ) {
        self.models = models
        self.policyClient = policyClient
        self.enableDeterministic = enableDeterministic
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "QueryRouter")
    }

    // MARK: - Public API

    /// Route a conversation to the optimal model tier.
    ///
    /// - Parameter messages: Chat messages as dictionaries with "role" and "content" keys.
    /// - Returns: A routing decision including model name, tier, and optional deterministic result.
    public func route(messages: [[String: String]]) async -> QueryRoutingDecision {
        let policy = await resolvePolicy()
        let lastUserMessage = messages.last(where: { $0["role"] == "user" })?["content"] ?? ""

        // Deterministic interception.
        if enableDeterministic && policy.deterministicEnabled {
            if let result = tryDeterministic(lastUserMessage) {
                return QueryRoutingDecision(
                    modelName: "",
                    complexityScore: 0.0,
                    tier: "deterministic",
                    strategy: "deterministic",
                    fallbackChain: [],
                    deterministicResult: result
                )
            }
        }

        // Complexity scoring.
        let score = computeComplexity(text: lastUserMessage, policy: policy)
        let tier = assignTier(score: score, policy: policy)
        let modelName = selectModel(tier: tier)
        let fallback = buildFallbackChain(primary: modelName)

        return QueryRoutingDecision(
            modelName: modelName,
            complexityScore: score,
            tier: tier,
            strategy: "complexity",
            fallbackChain: fallback,
            deterministicResult: nil
        )
    }

    /// Get the next fallback model when the given model fails.
    ///
    /// - Parameter failedModel: The model name that failed.
    /// - Returns: The next model in the fallback chain, or `nil` if none remain.
    public func getFallback(failedModel: String) -> String? {
        guard let info = models[failedModel] else { return nil }
        let currentIndex = Self.tierPriority.firstIndex(of: info.tier) ?? 0

        // Walk down from current tier to find a loaded alternative.
        for tierIndex in (0...currentIndex).reversed() {
            let tier = Self.tierPriority[tierIndex]
            if let candidate = models.values.first(where: {
                $0.tier == tier && $0.name != failedModel && $0.loaded
            }) {
                return candidate.name
            }
        }
        return nil
    }

    // MARK: - Private

    private func resolvePolicy() async -> RoutingPolicy {
        if let client = policyClient {
            return await client.getPolicy()
        }
        return defaultRoutingPolicy
    }

    /// Compute a 0.0-1.0 complexity score from word count and indicator matching.
    private func computeComplexity(text: String, policy: RoutingPolicy) -> Double {
        let words = text.split(separator: " ")
        let wordCount = words.count
        let fastMax = policy.thresholds.fastMaxWords
        let qualityMin = policy.thresholds.qualityMinWords

        // Word-count component: linear scale between thresholds.
        let wordScore: Double
        if wordCount <= fastMax {
            wordScore = 0.0
        } else if wordCount >= qualityMin {
            wordScore = 1.0
        } else {
            wordScore = Double(wordCount - fastMax) / Double(qualityMin - fastMax)
        }

        // Indicator component: fraction of complex indicators found.
        let lowerText = text.lowercased()
        let matchCount = policy.complexIndicators.filter { lowerText.contains($0) }.count
        let indicatorScore = min(Double(matchCount) / 3.0, 1.0)

        return min(wordScore * 0.6 + indicatorScore * 0.4, 1.0)
    }

    /// Map a complexity score to a tier name.
    private func assignTier(score: Double, policy: RoutingPolicy) -> String {
        if score < 0.3 {
            return "fast"
        } else if score >= 0.7 {
            return "quality"
        } else {
            return "balanced"
        }
    }

    /// Pick the best loaded model for the given tier, falling back to any loaded model.
    private func selectModel(tier: String) -> String {
        // Prefer a loaded model in the target tier.
        if let match = models.values.first(where: { $0.tier == tier && $0.loaded }) {
            return match.name
        }
        // Fall back to any loaded model.
        if let any = models.values.first(where: { $0.loaded }) {
            return any.name
        }
        // No loaded models — return the first in the target tier regardless.
        return models.values.first(where: { $0.tier == tier })?.name
            ?? models.values.first?.name
            ?? ""
    }

    /// Build a fallback chain excluding the primary model.
    private func buildFallbackChain(primary: String) -> [String] {
        return Self.tierPriority.compactMap { tier in
            models.values.first(where: { $0.tier == tier && $0.name != primary && $0.loaded })?.name
        }
    }

    /// Attempt to evaluate the query as pure arithmetic.
    private func tryDeterministic(_ text: String) -> DeterministicResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard Self.arithmeticPattern.firstMatch(in: trimmed, range: range) != nil else {
            return nil
        }

        // Extract the arithmetic expression (digits and operators only).
        let expression = trimmed
            .replacingOccurrences(of: "?", with: "")
            .components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+-*/^%. ")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)

        // Use NSExpression for safe evaluation of basic arithmetic.
        // Replace ^ with ** is not supported by NSExpression, so skip power expressions.
        guard !expression.contains("^") else { return nil }

        let nsExpression = NSExpression(format: expression)
        guard let result = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }

        return DeterministicResult(
            answer: result.stringValue,
            method: "arithmetic",
            confidence: 1.0
        )
    }
}

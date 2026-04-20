import Foundation
import os.log

/// HTTP client for the server-side runtime planner API.
///
/// Fetches runtime plans from `POST /api/v2/runtime/plan` and uploads
/// privacy-safe benchmark telemetry to `POST /api/v2/runtime/benchmarks`.
///
/// All network calls are best-effort: failures are logged and return `nil`
/// or `false` without throwing. The planner must never block inference on
/// a server round-trip.
public actor RuntimePlannerClient {

    // MARK: - Constants

    static let planPath = "/api/v2/runtime/plan"
    static let benchmarkPath = "/api/v2/runtime/benchmarks"
    static let defaultsPath = "/api/v2/runtime/defaults"

    // MARK: - Properties

    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "RuntimePlannerClient")

    // MARK: - Initialization

    /// Creates a new planner client.
    ///
    /// - Parameters:
    ///   - baseURL: Server base URL (default: `https://api.octomil.com`).
    ///   - apiKey: Bearer token for authentication.
    ///   - timeoutSeconds: Request timeout in seconds (default: 10).
    public init(
        baseURL: URL = URL(string: "https://api.octomil.com")!,
        apiKey: String? = nil,
        timeoutSeconds: TimeInterval = 10
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    /// Creates a planner client from an injected URLSession (for testing).
    internal init(
        baseURL: URL,
        apiKey: String?,
        session: URLSession
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    // MARK: - Plan Fetch

    /// Fetch a runtime plan from the server.
    ///
    /// Returns `nil` on any failure (network, decode, non-2xx). Never throws.
    ///
    /// - Parameters:
    ///   - model: Model identifier.
    ///   - capability: Capability string (e.g. "text", "embeddings").
    ///   - routingPolicy: Routing policy (e.g. "local_first", "cloud_only").
    ///   - device: The device runtime profile.
    ///   - allowCloudFallback: Whether cloud fallback is permitted.
    /// - Returns: Parsed ``RuntimePlanResponse``, or `nil` on failure.
    public func fetchPlan(
        model: String,
        capability: String,
        routingPolicy: String? = nil,
        device: DeviceRuntimeProfile,
        allowCloudFallback: Bool? = nil
    ) async -> RuntimePlanResponse? {
        let url = baseURL.appendingPathComponent(Self.planPath)

        var payload: [String: Any] = [
            "model": model,
            "capability": capability,
        ]

        // Encode device profile as nested dictionary
        if let deviceData = try? jsonEncoder.encode(device),
           let deviceDict = try? JSONSerialization.jsonObject(with: deviceData) as? [String: Any] {
            payload["device"] = deviceDict
        }

        if let routingPolicy {
            payload["routing_policy"] = routingPolicy
        }
        if let allowCloudFallback {
            payload["allow_cloud_fallback"] = allowCloudFallback
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("octomil-ios/\(OctomilVersion.current)", forHTTPHeaderField: "User-Agent")
            configureAuth(&request)

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                logger.warning("Plan fetch returned HTTP \(statusCode)")
                return nil
            }

            return try jsonDecoder.decode(RuntimePlanResponse.self, from: data)
        } catch {
            logger.debug("Plan fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Benchmark Upload

    /// Upload privacy-safe benchmark telemetry to the server.
    ///
    /// The payload must NOT contain any user prompts, responses, file paths,
    /// or personally identifying information. Only hardware/engine metrics
    /// are sent.
    ///
    /// - Parameter payload: Privacy-safe benchmark payload.
    /// - Returns: `true` if the upload succeeded.
    public func uploadBenchmark(_ payload: [String: Any]) async -> Bool {
        let url = baseURL.appendingPathComponent(Self.benchmarkPath)

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("octomil-ios/\(OctomilVersion.current)", forHTTPHeaderField: "User-Agent")
            configureAuth(&request)

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                logger.debug("Benchmark upload returned HTTP \(statusCode)")
                return false
            }

            return true
        } catch {
            logger.debug("Benchmark upload failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Defaults

    /// Response from `GET /api/v2/runtime/defaults`.
    public struct RuntimeDefaultsResponse: Codable, Sendable {
        /// Default routing policy.
        public let defaultPolicy: String
        /// Default plan TTL in seconds.
        public let defaultPlanTtlSeconds: Int
        /// Supported routing policies.
        public let supportedPolicies: [String]

        enum CodingKeys: String, CodingKey {
            case defaultPolicy = "default_policy"
            case defaultPlanTtlSeconds = "default_plan_ttl_seconds"
            case supportedPolicies = "supported_policies"
        }
    }

    /// Fetch runtime defaults from the server.
    ///
    /// Returns `nil` on any failure (network, decode, non-2xx). Never throws.
    public func fetchDefaults() async -> RuntimeDefaultsResponse? {
        let url = baseURL.appendingPathComponent(Self.defaultsPath)

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("octomil-ios/\(OctomilVersion.current)", forHTTPHeaderField: "User-Agent")
            configureAuth(&request)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                logger.debug("Defaults fetch returned HTTP \(statusCode)")
                return nil
            }

            return try jsonDecoder.decode(RuntimeDefaultsResponse.self, from: data)
        } catch {
            logger.debug("Defaults fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Typed Benchmark Submission

    /// Submit a privacy-safe benchmark using the typed ``RuntimeBenchmarkSubmission``.
    ///
    /// This is a convenience wrapper around ``uploadBenchmark(_:)`` that
    /// enforces the banned-keys policy at the type level.
    ///
    /// - Parameter submission: The benchmark submission.
    /// - Returns: `true` if the upload succeeded.
    public func submitBenchmark(_ submission: RuntimeBenchmarkSubmission) async -> Bool {
        await uploadBenchmark(submission.toDictionary())
    }

    // MARK: - Private

    private func configureAuth(_ request: inout URLRequest) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }
}

import Foundation
import os.log

// MARK: - EmbeddingUsage

/// Token usage statistics from the embeddings endpoint.
public struct EmbeddingUsage: Sendable, Equatable, Codable {
    /// Number of tokens in the input.
    public let promptTokens: Int

    /// Total tokens consumed.
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - EmbeddingResult

/// Result returned by ``EmbeddingClient/embed(modelId:input:)``.
public struct EmbeddingResult: Sendable, Equatable {
    /// Dense embedding vectors, one per input string.
    public let embeddings: [[Double]]

    /// The model that produced the embeddings.
    public let model: String

    /// Token usage statistics.
    public let usage: EmbeddingUsage
}

// MARK: - EmbeddingClient

/// Calls `POST /api/v1/embeddings` and returns dense vectors.
///
/// Usage:
/// ```swift
/// let client = EmbeddingClient(
///     serverURL: URL(string: "https://api.octomil.com")!,
///     apiKey: "your-key"
/// )
/// let result = try await client.embed(
///     modelId: "nomic-embed-text",
///     input: "Hello, world!"
/// )
/// print(result.embeddings) // [[0.1, 0.2, ...]]
/// ```
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public final class EmbeddingClient: @unchecked Sendable {

    private let serverURL: URL
    private let apiKey: String
    private let session: URLSession
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "EmbeddingClient")

    public init(serverURL: URL, apiKey: String, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Generate embeddings for a single string.
    ///
    /// - Parameters:
    ///   - modelId: Embedding model identifier (e.g. `"nomic-embed-text"`).
    ///   - input: Text to embed.
    /// - Returns: An ``EmbeddingResult`` with the dense vector.
    public func embed(modelId: String, input: String) async throws -> EmbeddingResult {
        let payload: [String: Any] = [
            "model_id": modelId,
            "input": input,
        ]
        return try await sendRequest(payload: payload)
    }

    /// Generate embeddings for multiple strings.
    ///
    /// - Parameters:
    ///   - modelId: Embedding model identifier (e.g. `"nomic-embed-text"`).
    ///   - input: Array of texts to embed.
    /// - Returns: An ``EmbeddingResult`` with one vector per input string.
    public func embed(modelId: String, input: [String]) async throws -> EmbeddingResult {
        let payload: [String: Any] = [
            "model_id": modelId,
            "input": input,
        ]
        return try await sendRequest(payload: payload)
    }

    // MARK: - Private

    private func sendRequest(payload: [String: Any]) async throws -> EmbeddingResult {
        let url = serverURL.appendingPathComponent("api/v1/embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OctomilError.serverError(
                statusCode: code,
                message: "Embeddings request failed"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw OctomilError.decodingError(underlying: "Invalid embeddings response format")
        }

        let embeddings: [[Double]] = dataArray.compactMap { item in
            item["embedding"] as? [Double]
        }

        let model = json["model"] as? String ?? ""

        let usageDict = json["usage"] as? [String: Any] ?? [:]
        let usage = EmbeddingUsage(
            promptTokens: usageDict["prompt_tokens"] as? Int ?? 0,
            totalTokens: usageDict["total_tokens"] as? Int ?? 0
        )

        return EmbeddingResult(
            embeddings: embeddings,
            model: model,
            usage: usage
        )
    }
}

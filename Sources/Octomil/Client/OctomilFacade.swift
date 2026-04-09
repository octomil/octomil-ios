import Foundation

/// Simplified entry point for the Octomil SDK.
///
/// Wraps ``OctomilClient`` with a streamlined API for common operations.
///
/// ```swift
/// let octomil = Octomil(publishableKey: "oct_pub_live_...")
/// try await octomil.initialize()
/// let response = try await octomil.responses.create(model: "phi-4-mini", input: "Hello")
/// print(response.outputText)
/// ```
public final class Octomil: @unchecked Sendable {
    private var initialized = false
    private let authConfig: AuthConfig
    private var client: OctomilClient?
    private var _embeddings: FacadeEmbeddings?

    /// Creates a facade using a publishable key (mobile/edge SDKs).
    public init(publishableKey: String) {
        self.authConfig = .publishableKey(publishableKey)
    }

    /// Creates a facade using an organization API key (server-side / CI).
    public init(apiKey: String, orgId: String, serverURL: URL = OctomilClient.defaultServerURL) {
        self.authConfig = .orgApiKey(apiKey: apiKey, orgId: orgId, serverURL: serverURL)
    }

    /// Initializes the underlying client. Idempotent.
    public func initialize() async throws {
        guard !initialized else { return }
        client = OctomilClient(auth: authConfig)

        let embeddingClient = EmbeddingClient(
            serverURL: authConfig.serverURL,
            apiKey: authConfig.token
        )
        _embeddings = FacadeEmbeddings(embeddingClient: embeddingClient)

        initialized = true
    }

    /// Response API namespace. Throws ``OctomilNotInitializedError`` if ``initialize()`` has not been called.
    public var responses: FacadeResponses {
        get throws {
            guard initialized, let client = client else {
                throw OctomilNotInitializedError()
            }
            return FacadeResponses(underlying: client.responses)
        }
    }

    /// Embeddings namespace. Throws ``OctomilNotInitializedError`` if ``initialize()`` has not been called.
    public var embeddings: FacadeEmbeddings {
        get throws {
            guard initialized, let emb = _embeddings else {
                throw OctomilNotInitializedError()
            }
            return emb
        }
    }
}

/// Error thrown when accessing facade APIs before calling ``Octomil/initialize()``.
public struct OctomilNotInitializedError: Error, LocalizedError {
    public var errorDescription: String? {
        "Octomil client is not initialized. Call try await client.initialize() first."
    }
}

/// Convenience wrapper around ``OctomilResponses`` with simplified method signatures.
public final class FacadeResponses: @unchecked Sendable {
    private let underlying: OctomilResponses

    internal init(underlying: OctomilResponses) {
        self.underlying = underlying
    }

    /// Creates a response with a model name and plain-text input.
    public func create(model: String, input: String) async throws -> Response {
        let request = ResponseRequest(model: model, input: input)
        return try await underlying.create(request)
    }

    /// Streams a response with a model name and plain-text input.
    public func stream(model: String, input: String) -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        let request = ResponseRequest(model: model, input: input, stream: true)
        return underlying.stream(request)
    }

    /// Creates a response from a full ``ResponseRequest``.
    public func create(_ request: ResponseRequest) async throws -> Response {
        try await underlying.create(request)
    }

    /// Streams a response from a full ``ResponseRequest``.
    public func stream(_ request: ResponseRequest) -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        underlying.stream(request)
    }
}

/// Embeddings namespace on the unified Octomil facade.
///
/// Wraps ``EmbeddingClient`` with a simplified API that mirrors the
/// OpenAI-style `client.embeddings.create(...)` pattern.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public final class FacadeEmbeddings: @unchecked Sendable {
    private let embeddingClient: EmbeddingClient

    init(embeddingClient: EmbeddingClient) {
        self.embeddingClient = embeddingClient
    }

    /// Create embeddings for a single input string.
    ///
    /// - Parameters:
    ///   - model: Embedding model identifier (e.g. `"nomic-embed-text-v1.5"`).
    ///   - input: Text to embed.
    /// - Returns: An ``EmbeddingResult`` with the dense vector.
    public func create(model: String, input: String) async throws -> EmbeddingResult {
        try await embeddingClient.embed(modelId: model, input: input)
    }

    /// Create embeddings for multiple input strings.
    ///
    /// - Parameters:
    ///   - model: Embedding model identifier (e.g. `"nomic-embed-text-v1.5"`).
    ///   - input: Array of texts to embed.
    /// - Returns: An ``EmbeddingResult`` with one vector per input string.
    public func create(model: String, input: [String]) async throws -> EmbeddingResult {
        try await embeddingClient.embed(modelId: model, input: input)
    }
}

import Foundation

/// Simplified entry point for the Octomil SDK.
///
/// Wraps ``OctomilClient`` with a streamlined API for common operations.
///
/// ```swift
/// let octomil = OctomilSDK(publishableKey: "oct_pub_live_...")
/// try await octomil.initialize()
/// let response = try await octomil.responses.create(model: "phi-4-mini", input: "Hello")
/// print(response.outputText)
/// ```
public final class OctomilSDK: @unchecked Sendable {
    private var initialized = false
    private let authConfig: AuthConfig
    private var client: OctomilClient?

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
}

/// Error thrown when accessing facade APIs before calling ``OctomilSDK/initialize()``.
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

import Foundation

/// Stub cloud runtime for remote model inference.
///
/// Currently throws — will be wired to a real HTTP backend in a future release.
public final class CloudModelRuntime: ModelRuntime, @unchecked Sendable {
    public let serverURL: String
    public let apiKey: String

    public init(serverURL: String, apiKey: String) {
        self.serverURL = serverURL
        self.apiKey = apiKey
    }

    public var capabilities: RuntimeCapabilities {
        RuntimeCapabilities(supportsToolCalls: true, supportsStructuredOutput: true, supportsStreaming: true)
    }

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        throw OctomilResponsesError.runtimeNotFound("Cloud runtime not yet configured")
    }

    public func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { throw OctomilResponsesError.runtimeNotFound("Cloud runtime not yet configured") }
    }

    public func close() {}
}

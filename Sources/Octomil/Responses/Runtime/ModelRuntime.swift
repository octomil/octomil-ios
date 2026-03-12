import Foundation

/// Typed interface for on-device model inference (Layer 1).
///
/// Each concrete runtime wraps a specific engine (MLX, MediaPipe, llama.cpp, etc.)
/// and exposes a uniform request/response API.
public protocol ModelRuntime: Sendable {
    var capabilities: RuntimeCapabilities { get }
    func run(request: RuntimeRequest) async throws -> RuntimeResponse
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error>
    func close()
}

/// Factory that creates a ``ModelRuntime`` for a given model ID.
public typealias RuntimeFactory = @Sendable (String) -> ModelRuntime?

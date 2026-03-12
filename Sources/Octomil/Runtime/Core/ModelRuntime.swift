import Foundation

/// The foundational inference abstraction in the Octomil SDK (Layer 1).
///
/// Any execution backend that satisfies `run` and `stream` is a valid
/// `ModelRuntime` — whether it runs inference locally on-device (MLX,
/// MediaPipe, llama.cpp, CoreML) or delegates to a remote cloud endpoint.
///
/// The protocol intentionally imposes no constraints on *how* inference is
/// performed. This means:
///
/// - **Local runtimes** load model weights, manage GPU/ANE resources, and
///   produce tokens directly on the device.
/// - **Cloud runtimes** forward the ``RuntimeRequest`` to a remote API,
///   parse the response, and stream chunks back to the caller.
/// - **Hybrid runtimes** (e.g. ``RouterModelRuntime``) compose multiple
///   backends and select one based on a ``InferenceRoutingPolicy``.
///
/// Conforming types must be `Sendable` so that the ``OctomilResponses``
/// layer (Layer 2) can safely call them from any concurrency context.
///
/// ## Implementing a custom runtime
///
/// ```swift
/// final class MyLocalRuntime: ModelRuntime {
///     let capabilities = RuntimeCapabilities(supportsStreaming: true)
///
///     func run(request: RuntimeRequest) async throws -> RuntimeResponse {
///         // Perform full inference and return the completed response.
///     }
///
///     func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
///         // Yield chunks as they are produced.
///     }
///
///     func close() {
///         // Release model weights, GPU contexts, etc.
///     }
/// }
/// ```
///
/// Register your runtime with ``ModelRuntimeRegistry`` or supply it via
/// the `runtimeResolver` closure on ``OctomilResponses``.
public protocol ModelRuntime: Sendable {
    /// Declares the capabilities of this runtime (tool calls, streaming, etc.).
    var capabilities: RuntimeCapabilities { get }

    /// Run inference to completion and return the full response.
    func run(request: RuntimeRequest) async throws -> RuntimeResponse

    /// Run inference and stream partial results as they become available.
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error>

    /// Release any resources held by this runtime (model weights, GPU contexts, etc.).
    func close()
}

/// Factory that creates a ``ModelRuntime`` for a given model ID.
public typealias RuntimeFactory = @Sendable (String) -> ModelRuntime?

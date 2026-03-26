import Foundation

/// Pluggable protocol for on-device LLM inference.
///
/// Implement this to integrate any LLM runtime (MLX, llama.cpp, CoreML, etc.)
/// with the Octomil chat API.
///
/// ```swift
/// class MLXRuntime: LLMRuntime {
///     func generate(prompt: String, config: GenerateConfig) -> AsyncThrowingStream<String, Error> {
///         // MLX inference
///     }
/// }
///
/// // Register:
/// LLMRuntimeRegistry.shared.factory = { modelURL in
///     MLXRuntime(modelPath: modelURL)
/// }
/// ```
public protocol LLMRuntime: Sendable {
    /// Generate text from a prompt, yielding tokens as they are produced.
    func generate(prompt: String, config: GenerateConfig) -> AsyncThrowingStream<String, Error>

    /// Generate text from a multimodal input (text + media), yielding tokens as they are produced.
    func generateMultimodal(text: String, mediaData: Data, config: GenerateConfig) -> AsyncThrowingStream<String, Error>

    /// Whether this runtime supports vision (image) inputs.
    func supportsVision() -> Bool

    /// Whether this runtime supports audio inputs.
    func supportsAudio() -> Bool

    /// Release resources held by this runtime.
    func close()
}

/// Error thrown when a runtime operation is not supported.
public struct UnsupportedRuntimeOperation: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public extension LLMRuntime {
    func generateMultimodal(text: String, mediaData: Data, config: GenerateConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: UnsupportedRuntimeOperation("Multimodal not supported by this runtime"))
        }
    }

    func supportsVision() -> Bool { false }
    func supportsAudio() -> Bool { false }
}

/// Deprecated: use ``GenerationConfig`` instead.
///
/// This typealias preserves backward compatibility for existing ``LLMRuntime``
/// conformers that reference `GenerateConfig` in their method signatures.
@available(*, deprecated, renamed: "GenerationConfig")
public typealias GenerateConfig = GenerationConfig

/// Global registry for LLM runtimes.
///
/// Apps register their LLM runtime at initialization. The Octomil SDK
/// uses it when creating chat interfaces.
///
/// ```swift
/// // In AppDelegate or @main App init:
/// LLMRuntimeRegistry.shared.factory = { modelURL in
///     MLXRuntime(modelPath: modelURL)
/// }
/// ```
public final class LLMRuntimeRegistry: @unchecked Sendable {
    public static let shared = LLMRuntimeRegistry()

    /// Factory that creates an ``LLMRuntime`` for a given model URL.
    ///
    /// Set this before calling ``OctomilChat/init``. If nil, the SDK falls back
    /// to the built-in ``LLMEngine`` which may be a stub.
    public var factory: (@Sendable (URL) -> LLMRuntime)?

    private init() {}
}

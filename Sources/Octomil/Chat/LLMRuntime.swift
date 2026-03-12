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

    /// Release resources held by this runtime.
    func close()
}

/// Configuration for text generation.
public struct GenerateConfig: Sendable {
    /// Maximum tokens to generate.
    public let maxTokens: Int
    /// Sampling temperature.
    public let temperature: Double
    /// Top-p nucleus sampling.
    public let topP: Double
    /// Stop sequences.
    public let stop: [String]?

    public init(maxTokens: Int = 512, temperature: Double = 0.7, topP: Double = 1.0, stop: [String]? = nil) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
    }
}

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

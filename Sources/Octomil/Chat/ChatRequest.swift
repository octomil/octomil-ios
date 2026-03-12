import Foundation

/// Request parameters for a chat completion, mirroring OpenAI's request format.
///
/// ```swift
/// let request = ChatRequest(
///     messages: [.user("Hello")],
///     temperature: 0.7,
///     maxTokens: 256
/// )
/// ```
public struct ChatRequest: Sendable {
    /// The conversation messages.
    public let messages: [ChatMessage]
    /// Sampling temperature (0.0 = deterministic, 2.0 = very random).
    public let temperature: Double
    /// Maximum number of tokens to generate.
    public let maxTokens: Int
    /// Top-p nucleus sampling.
    public let topP: Double
    /// Tools the model may call.
    public let tools: [Tool]?
    /// Stop sequences that halt generation.
    public let stop: [String]?
    /// Optional per-request model override. When set, this takes precedence
    /// over the model name provided to the ``OctomilChat`` constructor.
    public let model: String?

    public init(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 512,
        topP: Double = 1.0,
        tools: [Tool]? = nil,
        stop: [String]? = nil,
        model: String? = nil
    ) {
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.tools = tools
        self.stop = stop
        self.model = model
    }
}

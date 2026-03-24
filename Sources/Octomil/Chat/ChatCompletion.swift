import Foundation

/// A chat completion response, mirroring the OpenAI Chat Completions API.
public struct ChatCompletion: Codable, Sendable {
    /// Unique identifier for this completion.
    public let id: String
    /// Always "chat.completion".
    public let object: String
    /// Unix timestamp when this completion was created.
    public let created: Int
    /// The model that generated this completion.
    public let model: String
    /// The list of completion choices.
    public let choices: [Choice]
    /// Token usage statistics.
    public let usage: Usage?

    public struct Choice: Codable, Sendable {
        public let index: Int
        public let message: ChatMessage
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    public struct Usage: Codable, Sendable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

/// A streamed chat completion chunk, mirroring OpenAI's streaming format.
public struct ChatCompletionChunk: Sendable {
    /// Unique identifier, same across all chunks in one generation.
    public let id: String
    /// Always "chat.completion.chunk".
    public let object: String
    /// Unix timestamp.
    public let created: Int
    /// The model name.
    public let model: String
    /// The list of chunk choices.
    public let choices: [ChunkChoice]

    public struct ChunkChoice: Sendable {
        public let index: Int
        public let delta: Delta
        public let finishReason: String?
    }

    public struct Delta: Sendable {
        public let role: ChatMessage.Role?
        public let content: String?
        public let toolCalls: [LegacyToolCall]?

        public init(role: ChatMessage.Role? = nil, content: String? = nil, toolCalls: [LegacyToolCall]? = nil) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
        }
    }
}

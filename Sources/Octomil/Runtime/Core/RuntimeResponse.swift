import Foundation

/// Response from a ``ModelRuntime``.
public struct RuntimeResponse: Sendable {
    public let text: String
    public let toolCalls: [RuntimeToolCall]?
    public let finishReason: String
    public let usage: RuntimeUsage?

    public init(
        text: String,
        toolCalls: [RuntimeToolCall]? = nil,
        finishReason: String = "stop",
        usage: RuntimeUsage? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }
}

/// A tool call produced by the runtime.
public struct RuntimeToolCall: Sendable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Token usage statistics.
public struct RuntimeUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

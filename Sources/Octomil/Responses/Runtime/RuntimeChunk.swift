import Foundation

/// A streaming chunk from a ``ModelRuntime``.
public struct RuntimeChunk: Sendable {
    public let text: String?
    public let toolCallDelta: RuntimeToolCallDelta?
    public let finishReason: String?
    public let usage: RuntimeUsage?

    public init(
        text: String? = nil,
        toolCallDelta: RuntimeToolCallDelta? = nil,
        finishReason: String? = nil,
        usage: RuntimeUsage? = nil
    ) {
        self.text = text
        self.toolCallDelta = toolCallDelta
        self.finishReason = finishReason
        self.usage = usage
    }
}

/// Incremental tool call data in a streaming chunk.
public struct RuntimeToolCallDelta: Sendable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let argumentsDelta: String?

    public init(index: Int, id: String? = nil, name: String? = nil, argumentsDelta: String? = nil) {
        self.index = index
        self.id = id
        self.name = name
        self.argumentsDelta = argumentsDelta
    }
}

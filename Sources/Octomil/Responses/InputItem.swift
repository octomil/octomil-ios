import Foundation

/// An input message in a response request.
public enum InputItem: Sendable {
    case system(String)
    case user([ContentPart])
    case assistant(content: [ContentPart]?, toolCalls: [ResponseToolCall]?)
    case toolResult(toolCallId: String, content: String)

    /// Convenience: create a user message with a single text part.
    public static func text(_ value: String) -> InputItem {
        .user([.text(value)])
    }

    /// Convenience: create a user message with multiple content parts.
    public static func userParts(_ parts: [ContentPart]) -> InputItem {
        .user(parts)
    }
}

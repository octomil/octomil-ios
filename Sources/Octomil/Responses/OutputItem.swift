import Foundation

/// An item in the response output.
public enum OutputItem: Sendable {
    case text(String)
    case toolCall(ResponseToolCall)
    case jsonOutput(String)
}

import Foundation

/// A tool call in the Response API layer.
public struct ResponseToolCall: Sendable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Convert to the legacy ``LegacyToolCall`` type.
    public func toLegacyToolCall() -> LegacyToolCall {
        LegacyToolCall(id: id, function: FunctionCall(name: name, arguments: arguments))
    }

    /// Create from a legacy ``LegacyToolCall``.
    public static func fromLegacy(_ toolCall: LegacyToolCall) -> ResponseToolCall {
        ResponseToolCall(id: toolCall.id, name: toolCall.function.name, arguments: toolCall.function.arguments)
    }
}

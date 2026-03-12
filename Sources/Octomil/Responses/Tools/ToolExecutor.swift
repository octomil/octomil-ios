import Foundation

/// Host-provided interface for executing tool calls (Layer 3).
///
/// The SDK invokes tools but does NOT execute them — that's the host app's job.
/// Implement this protocol to connect model tool calls to your app's functionality.
///
/// ```swift
/// class MyToolExecutor: ToolExecutor {
///     func execute(call: ResponseToolCall) async throws -> ToolResult {
///         switch call.name {
///         case "get_weather":
///             let weather = fetchWeather(call.arguments)
///             return ToolResult(toolCallId: call.id, content: weather)
///         default:
///             return ToolResult(toolCallId: call.id, content: "Unknown tool", isError: true)
///         }
///     }
/// }
/// ```
public protocol ToolExecutor: Sendable {
    func execute(call: ResponseToolCall) async throws -> ToolResult
}

/// The result of executing a tool call.
public struct ToolResult: Sendable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool

    public init(toolCallId: String, content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

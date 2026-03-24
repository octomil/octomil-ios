import Foundation

/// Result of a tool call execution.
public struct DomainToolResult: Codable, Sendable {
    public let id: String
    public let toolCallId: String
    public let messageId: String?
    public let output: String?
    public let outputRef: String?
    public let status: ToolCallStatus?
    public let sizeBytes: Int?
    public let isFinal: Bool

    public init(
        id: String,
        toolCallId: String,
        messageId: String? = nil,
        output: String? = nil,
        outputRef: String? = nil,
        status: ToolCallStatus? = nil,
        sizeBytes: Int? = nil,
        isFinal: Bool = true
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.messageId = messageId
        self.output = output
        self.outputRef = outputRef
        self.status = status
        self.sizeBytes = sizeBytes
        self.isFinal = isFinal
    }
}

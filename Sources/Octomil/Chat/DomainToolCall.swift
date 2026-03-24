import Foundation

/// Lifecycle status of a tool call.
public enum ToolCallStatus: String, Codable, Sendable {
    case requested
    case started
    case succeeded
    case failed
    case expired
}

/// Domain-level tool call entity. The existing ToolCall in Tool.swift is the wire format (LegacyToolCall).
public struct DomainToolCall: Codable, Sendable {
    public let id: String
    public let messageId: String
    public let threadId: String?
    public let name: String
    public let arguments: String?
    public let argumentsRef: String?
    public let status: ToolCallStatus?
    public let startedAt: String?
    public let endedAt: String?
    public let latencyMs: Int?
    public let errorCode: String?

    public init(
        id: String,
        messageId: String,
        threadId: String? = nil,
        name: String,
        arguments: String? = nil,
        argumentsRef: String? = nil,
        status: ToolCallStatus? = nil,
        startedAt: String? = nil,
        endedAt: String? = nil,
        latencyMs: Int? = nil,
        errorCode: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.threadId = threadId
        self.name = name
        self.arguments = arguments
        self.argumentsRef = argumentsRef
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.latencyMs = latencyMs
        self.errorCode = errorCode
    }
}

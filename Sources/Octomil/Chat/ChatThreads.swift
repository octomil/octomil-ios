import Foundation

public struct ChatThread: Codable, Sendable {
    public let id: String
    public let title: String?
    public let model: String
    public let bindingKey: String?
    public let storageMode: String?
    public let retentionPolicy: String?
    public let ttlSeconds: Int?
    public let createdAt: String
    public let updatedAt: String
    public let metadata: [String: AnyCodable]

    public init(
        id: String,
        title: String? = nil,
        model: String,
        bindingKey: String? = nil,
        storageMode: String? = nil,
        retentionPolicy: String? = nil,
        ttlSeconds: Int? = nil,
        createdAt: String,
        updatedAt: String,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.bindingKey = bindingKey
        self.storageMode = storageMode
        self.retentionPolicy = retentionPolicy
        self.ttlSeconds = ttlSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, title, model, metadata
        case bindingKey = "binding_key"
        case storageMode = "storage_mode"
        case retentionPolicy = "retention_policy"
        case ttlSeconds = "ttl_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct ChatTurnConfig: Codable, Sendable {
    public let maxTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let stop: [String]?

    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stop: [String]? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
    }
}

public struct ChatTurnRequest: Sendable {
    public let threadId: String
    public let input: String
    public let inputParts: [ContentPart]?
    public let config: ChatTurnConfig?
    public let storageMode: String?

    public init(
        threadId: String,
        input: String,
        inputParts: [ContentPart]? = nil,
        config: ChatTurnConfig? = nil,
        storageMode: String? = nil
    ) {
        self.threadId = threadId
        self.input = input
        self.inputParts = inputParts
        self.config = config
        self.storageMode = storageMode
    }

}

public struct GenerationMetrics: Codable, Sendable {
    public let ttftMs: Int
    public let decodeTokensPerSec: Double
    public let totalTokens: Int
    public let totalLatencyMs: Int

    public init(
        ttftMs: Int,
        decodeTokensPerSec: Double,
        totalTokens: Int,
        totalLatencyMs: Int
    ) {
        self.ttftMs = ttftMs
        self.decodeTokensPerSec = decodeTokensPerSec
        self.totalTokens = totalTokens
        self.totalLatencyMs = totalLatencyMs
    }
}

public struct ThreadMessage: Sendable {
    public let id: String
    public let threadId: String
    public let role: String
    public let content: String?
    public let contentParts: [ContentPart]?
    public let toolCalls: [LegacyToolCall]?
    public let toolCallId: String?
    public let parentMessageId: String?
    public let status: String?
    public let modelRef: String?
    public let storageMode: String?
    public let metrics: GenerationMetrics?
    public let createdAt: String

    public init(
        id: String,
        threadId: String,
        role: String,
        content: String? = nil,
        contentParts: [ContentPart]? = nil,
        toolCalls: [LegacyToolCall]? = nil,
        toolCallId: String? = nil,
        parentMessageId: String? = nil,
        status: String? = nil,
        modelRef: String? = nil,
        storageMode: String? = nil,
        metrics: GenerationMetrics? = nil,
        createdAt: String
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.contentParts = contentParts
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.parentMessageId = parentMessageId
        self.status = status
        self.modelRef = modelRef
        self.storageMode = storageMode
        self.metrics = metrics
        self.createdAt = createdAt
    }

}

public struct ChatTurnResult: Sendable {
    public let userMessage: ThreadMessage
    public let assistantMessage: ThreadMessage

    public init(userMessage: ThreadMessage, assistantMessage: ThreadMessage) {
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
    }

}

actor LocalChatThreadStore {
    static let shared = LocalChatThreadStore()

    private struct StoredThread {
        var thread: ChatThread
        var messages: [ThreadMessage]
    }

    private var threads: [String: StoredThread] = [:]

    func createThread(
        model: String,
        title: String?,
        metadata: [String: AnyCodable]
    ) -> ChatThread {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let thread = ChatThread(
            id: "thread_\(UUID().uuidString)",
            title: title,
            model: model,
            createdAt: timestamp,
            updatedAt: timestamp,
            metadata: metadata
        )
        threads[thread.id] = StoredThread(thread: thread, messages: [])
        return thread
    }

    func getThread(_ threadId: String) -> ChatThread? {
        threads[threadId]?.thread
    }

    func listThreads(limit: Int?, order: SortOrder) -> [ChatThread] {
        let sorted = threads.values
            .map(\.thread)
            .sorted { lhs, rhs in
                if order == .asc {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.createdAt > rhs.createdAt
            }
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func messages(for threadId: String) -> [ThreadMessage]? {
        threads[threadId]?.messages
    }

    func append(
        threadId: String,
        userMessage: ThreadMessage,
        assistantMessage: ThreadMessage
    ) throws {
        guard var stored = threads[threadId] else {
            throw OctomilError.invalidInput(reason: "Unknown thread id '\(threadId)'")
        }
        stored.messages.append(userMessage)
        stored.messages.append(assistantMessage)
        stored.thread = ChatThread(
            id: stored.thread.id,
            title: stored.thread.title,
            model: stored.thread.model,
            createdAt: stored.thread.createdAt,
            updatedAt: assistantMessage.createdAt,
            metadata: stored.thread.metadata
        )
        threads[threadId] = stored
    }
}

public enum SortOrder: String, Sendable {
    case asc
    case desc
}

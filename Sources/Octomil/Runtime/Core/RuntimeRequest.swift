import Foundation

/// A single content part within a runtime message.
/// Media parts hold raw decoded bytes (not base64).
public enum RuntimeContentPart: Sendable {
    case text(String)
    case image(data: Data, mediaType: String)
    case audio(data: Data, mediaType: String)
    case video(data: Data, mediaType: String)
}

/// A message in a runtime conversation.
public struct RuntimeMessage: Sendable {
    public let role: MessageRole
    public let parts: [RuntimeContentPart]

    public init(role: MessageRole, parts: [RuntimeContentPart]) {
        self.role = role
        self.parts = parts
    }
}

/// Generation parameters.
public struct GenerationConfig: Sendable {
    public let maxTokens: Int
    public let temperature: Double
    public let topP: Double
    public let stop: [String]?

    public init(maxTokens: Int = 512, temperature: Double = 0.7, topP: Double = 1.0, stop: [String]? = nil) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
    }
}

/// Request sent to a ``ModelRuntime``.
public struct RuntimeRequest: Sendable {
    public let messages: [RuntimeMessage]
    public let generationConfig: GenerationConfig
    public let toolDefinitions: [RuntimeToolDef]?
    public let jsonSchema: String?

    public init(
        messages: [RuntimeMessage],
        generationConfig: GenerationConfig = GenerationConfig(),
        toolDefinitions: [RuntimeToolDef]? = nil,
        jsonSchema: String? = nil
    ) {
        self.messages = messages
        self.generationConfig = generationConfig
        self.toolDefinitions = toolDefinitions
        self.jsonSchema = jsonSchema
    }
}

/// A tool definition passed to the runtime.
public struct RuntimeToolDef: Sendable {
    public let name: String
    public let description: String
    public let parametersSchema: String?

    public init(name: String, description: String, parametersSchema: String? = nil) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
    }
}

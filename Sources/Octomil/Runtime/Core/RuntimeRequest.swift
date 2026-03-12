import Foundation

/// Request sent to a ``ModelRuntime``.
public struct RuntimeRequest: Sendable {
    public let prompt: String
    public let maxTokens: Int
    public let temperature: Double
    public let topP: Double
    public let stop: [String]?
    public let toolDefinitions: [RuntimeToolDef]?
    public let jsonSchema: String?

    public init(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Double = 0.7,
        topP: Double = 1.0,
        stop: [String]? = nil,
        toolDefinitions: [RuntimeToolDef]? = nil,
        jsonSchema: String? = nil
    ) {
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
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

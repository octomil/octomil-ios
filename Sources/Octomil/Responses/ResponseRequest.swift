import Foundation

/// A request to the Response API.
public struct ResponseRequest: Sendable {
    public let model: String
    public let input: [InputItem]
    public let tools: [Tool]
    public let toolChoice: ToolChoice
    public let responseFormat: ResponseFormat
    public let stream: Bool
    public let maxOutputTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let stop: [String]?
    public let metadata: [String: String]?

    /// System prompt shorthand — prepended as a system message before input.
    public let instructions: String?

    /// Chain a conversation by referencing a prior response ID.
    public let previousResponseId: String?

    public init(
        model: String,
        input: [InputItem],
        tools: [Tool] = [],
        toolChoice: ToolChoice = .auto,
        responseFormat: ResponseFormat = .text,
        stream: Bool = false,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stop: [String]? = nil,
        metadata: [String: String]? = nil,
        instructions: String? = nil,
        previousResponseId: String? = nil
    ) {
        self.model = model
        self.input = input
        self.tools = tools
        self.toolChoice = toolChoice
        self.responseFormat = responseFormat
        self.stream = stream
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
        self.metadata = metadata
        self.instructions = instructions
        self.previousResponseId = previousResponseId
    }

    /// Convenience: create a request with a plain string input.
    public init(
        model: String,
        input: String,
        tools: [Tool] = [],
        toolChoice: ToolChoice = .auto,
        responseFormat: ResponseFormat = .text,
        stream: Bool = false,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stop: [String]? = nil,
        metadata: [String: String]? = nil,
        instructions: String? = nil,
        previousResponseId: String? = nil
    ) {
        self.init(
            model: model,
            input: [.text(input)],
            tools: tools,
            toolChoice: toolChoice,
            responseFormat: responseFormat,
            stream: stream,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            metadata: metadata,
            instructions: instructions,
            previousResponseId: previousResponseId
        )
    }
}

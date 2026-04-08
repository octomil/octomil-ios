import Foundation

/// A complete response from the Response API.
public struct Response: Sendable {
    public let id: String
    public let model: String
    public let output: [OutputItem]
    public let finishReason: String
    public let usage: ResponseUsage?

    public init(id: String, model: String, output: [OutputItem], finishReason: String, usage: ResponseUsage? = nil) {
        self.id = id
        self.model = model
        self.output = output
        self.finishReason = finishReason
        self.usage = usage
    }

    /// Concatenated text from all `.text` output items.
    public var outputText: String {
        output.compactMap { item in
            if case .text(let text) = item { return text }
            return nil
        }.joined()
    }
}

/// Token usage statistics for a response.
public struct ResponseUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

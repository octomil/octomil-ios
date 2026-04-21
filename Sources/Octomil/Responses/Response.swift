import Foundation

/// A complete response from the Response API.
public struct Response: Sendable {
    public let id: String
    public let model: String
    public let output: [OutputItem]
    public let finishReason: String
    public let usage: ResponseUsage?

    /// Privacy-safe routing metadata describing how this request was routed.
    ///
    /// Contains operational metadata only: route ID, planner source, locality,
    /// engine, fallback info, and model ref kind.
    /// NEVER contains: prompt, input, output, audio, filePath, or content.
    public let routeMetadata: RouteMetadata?

    public init(
        id: String,
        model: String,
        output: [OutputItem],
        finishReason: String,
        usage: ResponseUsage? = nil,
        routeMetadata: RouteMetadata? = nil
    ) {
        self.id = id
        self.model = model
        self.output = output
        self.finishReason = finishReason
        self.usage = usage
        self.routeMetadata = routeMetadata
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

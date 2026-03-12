import Foundation

/// Declares what a ``ModelRuntime`` implementation supports.
public struct RuntimeCapabilities: Sendable {
    public let supportsToolCalls: Bool
    public let supportsStructuredOutput: Bool
    public let supportsMultimodalInput: Bool
    public let supportsStreaming: Bool
    public let maxContextLength: Int?
    public let supportedFamilies: Set<String>

    public init(
        supportsToolCalls: Bool = false,
        supportsStructuredOutput: Bool = false,
        supportsMultimodalInput: Bool = false,
        supportsStreaming: Bool = true,
        maxContextLength: Int? = nil,
        supportedFamilies: Set<String> = []
    ) {
        self.supportsToolCalls = supportsToolCalls
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsMultimodalInput = supportsMultimodalInput
        self.supportsStreaming = supportsStreaming
        self.maxContextLength = maxContextLength
        self.supportedFamilies = supportedFamilies
    }
}

import Foundation

/// Bridges an existing ``LLMRuntime`` to the ``ModelRuntime`` protocol.
///
/// Zero changes to existing `LLMRuntime` implementations — this adapter
/// handles the translation between the old token-stream API and the new
/// typed request/response API.
public final class LLMRuntimeAdapter: ModelRuntime, @unchecked Sendable {
    private let llmRuntime: LLMRuntime
    public let capabilities: RuntimeCapabilities

    public init(
        llmRuntime: LLMRuntime,
        capabilities: RuntimeCapabilities = RuntimeCapabilities(
            supportsToolCalls: false,
            supportsStructuredOutput: false,
            supportsMultimodalInput: false,
            supportsStreaming: true
        )
    ) {
        self.llmRuntime = llmRuntime
        self.capabilities = capabilities
    }

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        let config = makeConfig(from: request)
        var tokens: [String] = []

        for try await token in llmRuntime.generate(prompt: request.prompt, config: config) {
            tokens.append(token)
        }

        let text = tokens.joined()
        return RuntimeResponse(
            text: text,
            finishReason: "stop",
            usage: RuntimeUsage(
                promptTokens: estimateTokens(request.prompt),
                completionTokens: tokens.count,
                totalTokens: estimateTokens(request.prompt) + tokens.count
            )
        )
    }

    public func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        let config = makeConfig(from: request)
        let runtime = llmRuntime

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await token in runtime.generate(prompt: request.prompt, config: config) {
                        continuation.yield(RuntimeChunk(text: token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func close() {
        llmRuntime.close()
    }

    private func makeConfig(from request: RuntimeRequest) -> GenerateConfig {
        GenerateConfig(
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            topP: request.topP,
            stop: request.stop
        )
    }

    private func estimateTokens(_ text: String) -> Int {
        text.split(separator: " ").count
    }
}

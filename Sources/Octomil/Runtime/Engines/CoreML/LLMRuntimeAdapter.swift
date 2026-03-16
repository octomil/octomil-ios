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
        capabilities: RuntimeCapabilities? = nil
    ) {
        self.llmRuntime = llmRuntime
        self.capabilities = capabilities ?? RuntimeCapabilities(
            supportsToolCalls: false,
            supportsStructuredOutput: false,
            supportsMultimodalInput: llmRuntime.supportsVision() || llmRuntime.supportsAudio(),
            supportsStreaming: true
        )
    }

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        let config = makeConfig(from: request)
        var tokens: [String] = []

        let stream: AsyncThrowingStream<String, Error>
        if let mediaData = request.mediaData {
            stream = llmRuntime.generateMultimodal(text: request.prompt, mediaData: mediaData, config: config)
        } else {
            stream = llmRuntime.generate(prompt: request.prompt, config: config)
        }

        for try await token in stream {
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
                    let tokenStream: AsyncThrowingStream<String, Error>
                    if let mediaData = request.mediaData {
                        tokenStream = runtime.generateMultimodal(text: request.prompt, mediaData: mediaData, config: config)
                    } else {
                        tokenStream = runtime.generate(prompt: request.prompt, config: config)
                    }
                    for try await token in tokenStream {
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

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
        let prompt = ChatMLRenderer.render(request)
        let config = makeConfig(from: request)
        var tokens: [String] = []

        let mediaData = Self.extractMediaData(from: request)
        let stream: AsyncThrowingStream<String, Error>
        if let mediaData = mediaData {
            stream = llmRuntime.generateMultimodal(text: prompt, mediaData: mediaData, config: config)
        } else {
            stream = llmRuntime.generate(prompt: prompt, config: config)
        }

        for try await token in stream {
            tokens.append(token)
        }

        let text = tokens.joined()
        return RuntimeResponse(
            text: text,
            finishReason: "stop",
            usage: RuntimeUsage(
                promptTokens: estimateTokens(prompt),
                completionTokens: tokens.count,
                totalTokens: estimateTokens(prompt) + tokens.count
            )
        )
    }

    public func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        let prompt = ChatMLRenderer.render(request)
        let config = makeConfig(from: request)
        let runtime = llmRuntime
        let mediaData = Self.extractMediaData(from: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let tokenStream: AsyncThrowingStream<String, Error>
                    if let mediaData = mediaData {
                        tokenStream = runtime.generateMultimodal(text: prompt, mediaData: mediaData, config: config)
                    } else {
                        tokenStream = runtime.generate(prompt: prompt, config: config)
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

    private static func extractMediaData(from request: RuntimeRequest) -> Data? {
        for msg in request.messages {
            for part in msg.parts {
                switch part {
                case .image(let data, _), .audio(let data, _), .video(let data, _):
                    return data
                default: continue
                }
            }
        }
        return nil
    }

    private func makeConfig(from request: RuntimeRequest) -> GenerateConfig {
        GenerateConfig(
            maxTokens: request.generationConfig.maxTokens,
            temperature: request.generationConfig.temperature,
            topP: request.generationConfig.topP,
            stop: request.generationConfig.stop
        )
    }

    private func estimateTokens(_ text: String) -> Int {
        text.split(separator: " ").count
    }
}

import Foundation

/// A ``ModelRuntime`` backed by a local file on disk.
///
/// This runtime wraps a file URL and delegates actual engine creation
/// to ``EngineRegistry``. It does NOT pick the engine itself — the
/// registry decides based on modality and file extension.
///
/// Used by ``ModelCatalogService`` for both bundled and downloaded models.
public final class LocalFileModelRuntime: ModelRuntime, @unchecked Sendable {

    /// Catalog model identifier.
    public let modelId: String

    /// File URL of the model artifact on disk.
    public let fileURL: URL

    /// Resolved engine, lazily created on first use.
    private var engine: StreamingInferenceEngine?
    private let lock = NSLock()

    public let capabilities: RuntimeCapabilities

    /// - Parameters:
    ///   - modelId: Catalog model identifier.
    ///   - fileURL: File URL pointing to the local model artifact.
    ///   - capabilities: Override capabilities. Defaults to streaming-only.
    public init(
        modelId: String,
        fileURL: URL,
        capabilities: RuntimeCapabilities = RuntimeCapabilities(supportsStreaming: true)
    ) {
        self.modelId = modelId
        self.fileURL = fileURL
        self.capabilities = capabilities
    }

    // MARK: - ModelRuntime

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        let eng = try resolveEngine()
        var tokens: [String] = []

        for try await chunk in eng.generate(input: request.prompt, modality: .text) {
            if let text = String(data: chunk.data, encoding: .utf8) {
                tokens.append(text)
            }
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
        let fileURL = self.fileURL

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let eng: StreamingInferenceEngine
                    let inferredEngine = EngineRegistry.engineFromURL(fileURL)
                    eng = try EngineRegistry.shared.resolve(
                        modality: .text,
                        engine: inferredEngine,
                        modelURL: fileURL
                    )

                    for try await chunk in eng.generate(input: request.prompt, modality: .text) {
                        if let text = String(data: chunk.data, encoding: .utf8) {
                            continuation.yield(RuntimeChunk(text: text))
                        }
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
        lock.lock()
        engine = nil
        lock.unlock()
    }

    // MARK: - Private

    private func resolveEngine() throws -> StreamingInferenceEngine {
        lock.lock()
        defer { lock.unlock() }

        if let existing = engine { return existing }

        let inferredEngine = EngineRegistry.engineFromURL(fileURL)
        let resolved = try EngineRegistry.shared.resolve(
            modality: .text,
            engine: inferredEngine,
            modelURL: fileURL
        )
        engine = resolved
        return resolved
    }

    private func estimateTokens(_ text: String) -> Int {
        text.split(separator: " ").count
    }
}

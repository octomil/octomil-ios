import Foundation

/// A ``ModelRuntime`` backed by a local file on disk.
///
/// This runtime wraps a file URL and delegates actual engine creation
/// to ``EngineRegistry``. It does NOT pick the engine itself — the
/// registry decides based on modality and file extension.
///
/// Used by ``ModelCatalogService`` for both bundled and downloaded models.
///
/// ## Multimodal / multi-resource support
///
/// When ``resourceBindings`` is provided, the runtime exposes resolved
/// file URLs for each resource kind (weights, projector, processor, etc.).
/// Engine factories can use ``resolvedResource(_:)`` to look up sidecar
/// files without relying on filename heuristics.
public final class LocalFileModelRuntime: ModelRuntime, @unchecked Sendable {

    /// Catalog model identifier.
    public let modelId: String

    /// File URL of the primary model artifact on disk.
    ///
    /// For single-resource packages this is the only artifact. For
    /// multi-resource packages this should point to the primary weights file.
    public let fileURL: URL

    /// Explicit resource bindings mapping ``ArtifactResourceKind`` to file URLs.
    ///
    /// When non-empty, engines should use ``resolvedResource(_:)`` to locate
    /// files instead of pattern-matching against the filesystem.
    public let resourceBindings: [ArtifactResourceKind: URL]

    /// Executor-specific configuration hints.
    public let engineConfig: EngineConfig?

    /// Resolved engine, lazily created on first use.
    private var engine: StreamingInferenceEngine?
    private let lock = NSLock()

    public let capabilities: RuntimeCapabilities

    /// Creates a runtime for a single-resource model.
    ///
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
        self.resourceBindings = [:]
        self.engineConfig = nil
        self.capabilities = capabilities
    }

    /// Creates a runtime for a multi-resource model with explicit resource bindings.
    ///
    /// - Parameters:
    ///   - modelId: Catalog model identifier.
    ///   - fileURL: File URL pointing to the primary model artifact (weights).
    ///   - resourceBindings: Mapping of resource kinds to their resolved file URLs.
    ///   - engineConfig: Optional executor-specific configuration hints.
    ///   - capabilities: Override capabilities.
    public init(
        modelId: String,
        fileURL: URL,
        resourceBindings: [ArtifactResourceKind: URL],
        engineConfig: EngineConfig? = nil,
        capabilities: RuntimeCapabilities = RuntimeCapabilities(supportsStreaming: true)
    ) {
        self.modelId = modelId
        self.fileURL = fileURL
        self.resourceBindings = resourceBindings
        self.engineConfig = engineConfig
        self.capabilities = capabilities
    }

    // MARK: - Resource Resolution

    /// Resolve the file URL for a specific resource kind.
    ///
    /// Checks ``resourceBindings`` first; falls back to ``fileURL`` for `.weights`.
    ///
    /// - Parameter kind: The resource kind to resolve.
    /// - Returns: The file URL, or nil if no binding exists for this kind.
    public func resolvedResource(_ kind: ArtifactResourceKind) -> URL? {
        if let url = resourceBindings[kind] {
            return url
        }
        // Fall back: for .weights, the primary fileURL is the implicit binding
        if kind == .weights {
            return fileURL
        }
        return nil
    }

    /// Whether this runtime has a projector resource available.
    ///
    /// This is a convenience check for multimodal (vision-language) models
    /// that require a separate projector file for image encoding.
    public var hasProjector: Bool {
        resourceBindings[.projector] != nil
    }

    // MARK: - ModelRuntime

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        // Determine modality from the request's mediaType.
        let modality = Self.modality(for: request)
        let input: Any = Self.engineInput(for: request)
        let eng = try resolveEngine(modality: modality)

        var tokens: [String] = []
        for try await chunk in eng.generate(input: input, modality: modality) {
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
        let modality = Self.modality(for: request)
        let input: Any = Self.engineInput(for: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let inferredEngine = EngineRegistry.engineFromURL(fileURL)
                    let eng = try EngineRegistry.shared.resolve(
                        modality: modality,
                        engine: inferredEngine,
                        modelURL: fileURL
                    )

                    for try await chunk in eng.generate(input: input, modality: modality) {
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

    /// Determine the ``Modality`` from a ``RuntimeRequest``.
    ///
    /// Checks `mediaType` first; defaults to `.text` when absent.
    private static func modality(for request: RuntimeRequest) -> Modality {
        guard let mediaType = request.mediaType?.lowercased() else { return .text }
        switch mediaType {
        case "audio":  return .audio
        case "image":  return .image
        case "video":  return .video
        default:       return .text
        }
    }

    /// Extract the appropriate engine input from a ``RuntimeRequest``.
    ///
    /// For audio/image/video requests that carry `mediaData`, the raw `Data` is
    /// passed to the engine. For text requests, the prompt string is used.
    private static func engineInput(for request: RuntimeRequest) -> Any {
        if let mediaData = request.mediaData, request.mediaType != nil {
            return mediaData
        }
        return request.prompt
    }

    private func resolveEngine(modality: Modality) throws -> StreamingInferenceEngine {
        lock.lock()
        defer { lock.unlock() }

        if let existing = engine { return existing }

        let inferredEngine = EngineRegistry.engineFromURL(fileURL)
        let resolved = try EngineRegistry.shared.resolve(
            modality: modality,
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

import Foundation
import os.log

/// Bootstraps ``AppManifest`` entries into the ``ModelRuntimeRegistry``
/// and resolves runtimes by capability at call time.
///
/// The catalog service is the bridge between the declarative manifest
/// and the runtime system. It does NOT reference any specific engine
/// (GGUF, MLX, CoreML) — engine selection is delegated to
/// ``EngineRegistry`` and ``ModelRuntimeRegistry``.
public actor ModelCatalogService {

    // MARK: - State

    private let manifest: AppManifest
    private let modelManager: ModelManager
    private let readiness: ModelReadinessManager
    private let runtimeRegistry: ModelRuntimeRegistry
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelCatalog")

    /// Resolved runtimes keyed by capability.
    private var capabilityRuntimes: [ModelCapability: ModelRuntime] = [:]

    /// Cloud runtime factory, provided at init time for cloud-delivered models.
    private let cloudRuntimeFactory: ((String) -> ModelRuntime)?

    // MARK: - Init

    /// - Parameters:
    ///   - manifest: The app manifest describing desired models.
    ///   - modelManager: Manager for downloading managed models.
    ///   - readiness: Readiness tracker for managed downloads.
    ///   - runtimeRegistry: Registry to install resolved runtimes into.
    ///   - cloudRuntimeFactory: Optional factory to create cloud runtimes.
    public init(
        manifest: AppManifest,
        modelManager: ModelManager,
        readiness: ModelReadinessManager,
        runtimeRegistry: ModelRuntimeRegistry = .shared,
        cloudRuntimeFactory: ((String) -> ModelRuntime)? = nil
    ) {
        self.manifest = manifest
        self.modelManager = modelManager
        self.readiness = readiness
        self.runtimeRegistry = runtimeRegistry
        self.cloudRuntimeFactory = cloudRuntimeFactory
    }

    // MARK: - Bootstrap

    /// Walk every manifest entry and prepare its runtime.
    ///
    /// - Bundled: look up the file in Bundle.main, create a ``LocalFileModelRuntime``.
    /// - Managed: queue a background download via ``ModelReadinessManager``.
    /// - Cloud: register a cloud runtime immediately.
    ///
    /// Required entries that cannot be resolved throw ``OctomilError``.
    public func bootstrap() async throws {
        for entry in manifest.models {
            do {
                try await bootstrapEntry(entry)
            } catch {
                if entry.required {
                    throw error
                }
                logger.warning("Optional model '\(entry.id)' skipped: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Resolution

    /// Resolve a ``ModelRuntime`` for a given capability at call time.
    ///
    /// Returns the runtime registered during bootstrap, or nil if the
    /// capability is not in the manifest.
    public func runtime(for capability: ModelCapability) -> ModelRuntime? {
        capabilityRuntimes[capability]
    }

    /// Resolve a ``ModelRuntime`` for a model reference.
    public func runtime(for ref: ModelRef) -> ModelRuntime? {
        switch ref {
        case .id(let id):
            return runtimeRegistry.resolve(modelId: id)
        case .capability(let cap):
            return capabilityRuntimes[cap]
        }
    }

    // MARK: - Private

    private func bootstrapEntry(_ entry: AppModelEntry) async throws {
        switch entry.delivery {
        case .bundled:
            try bootstrapBundled(entry)
        case .managed:
            await bootstrapManaged(entry)
        case .cloud:
            try bootstrapCloud(entry)
        }
    }

    private func bootstrapBundled(_ entry: AppModelEntry) throws {
        guard let bundledPath = entry.bundledPath else {
            throw OctomilError.invalidRequest(reason: "Bundled model '\(entry.id)' has no bundledPath")
        }

        guard let url = Bundle.main.url(forResource: bundledPath, withExtension: nil) else {
            throw OctomilError.modelNotFound(modelId: "\(entry.id) (bundled path: \(bundledPath))")
        }

        let runtime = LocalFileModelRuntime(modelId: entry.id, fileURL: url)
        capabilityRuntimes[entry.capability] = runtime
        runtimeRegistry.register(family: entry.id) { _ in runtime }
        logger.info("Bundled model '\(entry.id)' registered for capability '\(entry.capability.rawValue)'")
    }

    private func bootstrapManaged(_ entry: AppModelEntry) async {
        // Check if a cached version is already available
        if let cached = modelManager.getCachedModel(modelId: entry.id) {
            let compiledURL = cached.compiledModelURL
            let runtime = LocalFileModelRuntime(modelId: entry.id, fileURL: compiledURL)
            capabilityRuntimes[entry.capability] = runtime
            runtimeRegistry.register(family: entry.id) { _ in runtime }
            logger.info("Managed model '\(entry.id)' loaded from cache")
            return
        }

        // Queue download — readiness manager will notify when complete
        await readiness.enqueue(entry: entry)
        logger.info("Managed model '\(entry.id)' queued for download")
    }

    private func bootstrapCloud(_ entry: AppModelEntry) throws {
        guard let factory = cloudRuntimeFactory else {
            throw OctomilError.runtimeUnavailable(reason: "No cloud runtime factory for model '\(entry.id)'")
        }
        let runtime = factory(entry.id)
        capabilityRuntimes[entry.capability] = runtime
        runtimeRegistry.register(family: entry.id) { _ in runtime }
        logger.info("Cloud model '\(entry.id)' registered for capability '\(entry.capability.rawValue)'")
    }

    /// Called by ``ModelReadinessManager`` when a managed download completes.
    public func onModelReady(entry: AppModelEntry, fileURL: URL) {
        let runtime = LocalFileModelRuntime(modelId: entry.id, fileURL: fileURL)
        capabilityRuntimes[entry.capability] = runtime
        runtimeRegistry.register(family: entry.id) { _ in runtime }
        logger.info("Managed model '\(entry.id)' now ready")
    }
}

import Foundation
import os.log

// MARK: - DownloadUpdate

/// Events emitted by ``ModelReadinessManager`` as managed models download.
public enum DownloadUpdate: Sendable {
    /// Download progress for a model.
    case progress(modelId: String, fraction: Double)
    /// Model download completed and the model is ready for inference.
    case ready(modelId: String)
    /// Model download failed.
    case failed(modelId: String, Error)
}

// MARK: - ModelReadinessManager

/// Orchestrates background downloads for managed models declared in the manifest.
///
/// Provides an ``AsyncStream`` of ``DownloadUpdate`` events and readiness queries.
public actor ModelReadinessManager {

    // MARK: - State

    private let modelManager: ModelManager
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelReadiness")

    /// Entries queued for download.
    private var pendingEntries: [AppModelEntry] = []

    /// Model IDs that have completed download.
    private var readyModelIds: Set<String> = []

    /// File URLs of ready models, keyed by model ID.
    private var readyURLs: [String: URL] = [:]

    /// Active download tasks.
    private var activeTasks: [String: Task<Void, Never>] = [:]

    /// Continuation for the download updates stream.
    private var updateContinuation: AsyncStream<DownloadUpdate>.Continuation?

    /// Waiters for awaitReady().
    private var readyWaiters: [String: [CheckedContinuation<URL, Error>]] = [:]

    // MARK: - Public Stream

    /// Stream of download update events.
    public let downloadUpdates: AsyncStream<DownloadUpdate>

    // MARK: - Init

    public init(modelManager: ModelManager) {
        self.modelManager = modelManager
        var continuation: AsyncStream<DownloadUpdate>.Continuation!
        self.downloadUpdates = AsyncStream<DownloadUpdate> { cont in
            continuation = cont
        }
        self.updateContinuation = continuation
    }

    // MARK: - Enqueue

    /// Queue a managed model entry for background download.
    public func enqueue(entry: AppModelEntry) {
        guard entry.delivery == .managed else { return }
        pendingEntries.append(entry)
        startDownload(entry: entry)
    }

    // MARK: - Readiness Queries

    /// Whether a model with the given capability is ready for inference.
    public func isReady(capability: ModelCapability, manifest: AppManifest) -> Bool {
        guard let entry = manifest.entry(for: capability) else { return false }
        return readyModelIds.contains(entry.id)
    }

    /// Whether a specific model ID is ready.
    public func isReady(modelId: String) -> Bool {
        readyModelIds.contains(modelId)
    }

    /// Wait until a model with the given capability is ready.
    ///
    /// Returns the file URL of the downloaded model.
    /// Throws if the download fails or the capability is not in the manifest.
    public func awaitReady(capability: ModelCapability, manifest: AppManifest) async throws -> URL {
        guard let entry = manifest.entry(for: capability) else {
            throw OctomilError.modelNotFound(modelId: "capability:\(capability.rawValue)")
        }
        return try await awaitReady(modelId: entry.id)
    }

    /// Wait until a specific model ID is ready.
    public func awaitReady(modelId: String) async throws -> URL {
        if let url = readyURLs[modelId] {
            return url
        }

        return try await withCheckedThrowingContinuation { continuation in
            var waiters = readyWaiters[modelId] ?? []
            waiters.append(continuation)
            readyWaiters[modelId] = waiters
        }
    }

    // MARK: - Private

    private func startDownload(entry: AppModelEntry) {
        let modelId = entry.id
        guard activeTasks[modelId] == nil else { return }

        let task = Task { [weak self] in
            do {
                guard let self = self else { return }
                let model = try await self.modelManager.downloadModel(modelId: modelId, version: "latest")
                let url = model.compiledModelURL
                await self.markReady(modelId: modelId, url: url)
            } catch {
                await self?.markFailed(modelId: modelId, error: error)
            }
        }
        activeTasks[modelId] = task
    }

    private func markReady(modelId: String, url: URL) {
        readyModelIds.insert(modelId)
        readyURLs[modelId] = url
        activeTasks[modelId] = nil
        updateContinuation?.yield(.ready(modelId: modelId))
        logger.info("Model '\(modelId)' is ready at \(url.path)")

        // Resume all waiters
        if let waiters = readyWaiters.removeValue(forKey: modelId) {
            for waiter in waiters {
                waiter.resume(returning: url)
            }
        }
    }

    private func markFailed(modelId: String, error: Error) {
        activeTasks[modelId] = nil
        updateContinuation?.yield(.failed(modelId: modelId, error))
        logger.error("Model '\(modelId)' download failed: \(error.localizedDescription)")

        // Resume all waiters with error
        if let waiters = readyWaiters.removeValue(forKey: modelId) {
            for waiter in waiters {
                waiter.resume(throwing: error)
            }
        }
    }
}

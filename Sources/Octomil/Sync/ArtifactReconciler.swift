import Foundation
import CryptoKit
import os.log

/// Downloads, verifies, stages, and activates model artifacts by reconciling
/// desired state from the server against local metadata.
///
/// Designed for use from both ``BackgroundSync`` (BG refresh tasks) and
/// foreground sync calls.
public actor ArtifactReconciler {

    // MARK: - Dependencies

    private let controlSync: ControlSync
    private let metadataStore: ModelMetadataStore
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "ArtifactReconciler")
    private let downloadSession: URLSession
    private let artifactDirectory: URL

    // MARK: - Initialization

    /// Creates a reconciler.
    ///
    /// - Parameters:
    ///   - controlSync: The control sync actor for fetching/reporting state.
    ///   - metadataStore: Persistent metadata store for installed artifacts.
    ///   - downloadSession: URL session for downloading artifacts (injectable for tests).
    ///   - artifactDirectory: Directory where downloaded artifacts are stored.
    public init(
        controlSync: ControlSync,
        metadataStore: ModelMetadataStore,
        downloadSession: URLSession = .shared,
        artifactDirectory: URL? = nil
    ) {
        self.controlSync = controlSync
        self.metadataStore = metadataStore
        self.downloadSession = downloadSession

        if let dir = artifactDirectory {
            self.artifactDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.artifactDirectory = appSupport.appendingPathComponent(
                "octomil/artifacts",
                isDirectory: true
            )
        }

        try? FileManager.default.createDirectory(
            at: self.artifactDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Reconcile

    /// Performs a full reconcile iteration.
    ///
    /// 1. Fetches desired state from the server.
    /// 2. Compares against local metadata.
    /// 3. Downloads, verifies, and stages new artifacts.
    /// 4. Activates artifacts per their activation policy.
    /// 5. Reports observed state back to the server.
    ///
    /// - Parameter deviceId: The server-assigned device identifier.
    /// - Returns: The list of actions taken during reconciliation.
    @discardableResult
    public func reconcile(deviceId: String) async throws -> [ReconcileAction] {
        // 1. Fetch desired state
        let desired = try await controlSync.fetchDesiredState(deviceId: deviceId)

        // 2. Determine actions
        let actions = planActions(desired: desired)

        // 3. Execute actions
        var completedActions: [ReconcileAction] = []

        for action in actions {
            switch action {
            case .download(let entry):
                let artifactId = entry.artifactManifest?.artifactId ?? ""
                do {
                    try await downloadAndStage(entry: entry)
                    // Activate according to policy
                    if entry.activationPolicy == "immediate" {
                        do {
                            try activateArtifact(artifactId: artifactId)
                            completedActions.append(.activate(
                                modelId: entry.modelId,
                                version: entry.desiredVersion
                            ))
                        } catch {
                            metadataStore.markFailed(artifactId: artifactId)
                            logger.error("Activation failed for \(artifactId): \(error.localizedDescription)")
                            completedActions.append(.download(entry))
                        }
                    } else {
                        completedActions.append(.download(entry))
                    }
                } catch {
                    logger.error("Download failed for \(artifactId): \(error.localizedDescription)")
                }

            case .activate(let modelId, let version):
                let matchingRecords = metadataStore.records(forModelId: modelId)
                if let record = matchingRecords.first(where: { $0.artifactVersion == version }) {
                    do {
                        try activateArtifact(artifactId: record.artifactId)
                        completedActions.append(action)
                    } catch {
                        metadataStore.markFailed(artifactId: record.artifactId)
                        logger.error("Activation failed for \(record.artifactId): \(error.localizedDescription)")
                    }
                }

            case .remove(let artifactId):
                removeArtifact(artifactId: artifactId)
                completedActions.append(action)

            case .upToDate:
                completedActions.append(action)
            }
        }

        // 5. Report observed state
        await reportCurrentState(deviceId: deviceId)

        return completedActions
    }

    /// Activates any staged artifacts whose activation policy is ``ActivationPolicy/nextLaunch``.
    ///
    /// Call this at app launch to handle `next_launch` policy artifacts.
    public func activateNextLaunchArtifacts() {
        let staged = metadataStore.stagedRecords()
        for record in staged {
            do {
                try activateArtifact(artifactId: record.artifactId)
                logger.info("Activated next-launch artifact: \(record.artifactId)")
            } catch {
                metadataStore.markFailed(artifactId: record.artifactId)
                logger.error("Failed to activate next-launch artifact \(record.artifactId): \(error.localizedDescription)")
            }
        }
    }

    /// Checks for crash-loop on the active artifact for a model and rolls back if needed.
    ///
    /// - Parameter modelId: The model to check.
    /// - Returns: `true` if a rollback was performed.
    @discardableResult
    public func checkAndRollbackIfNeeded(modelId: String) -> Bool {
        guard let active = metadataStore.activeRecord(forModelId: modelId) else {
            return false
        }

        metadataStore.incrementLaunchCount(artifactId: active.artifactId)

        guard metadataStore.shouldRollback(artifactId: active.artifactId) else {
            return false
        }

        logger.warning("Crash loop detected for \(active.artifactId), attempting rollback")

        // Find the previous staged/active version
        let allRecords = metadataStore.records(forModelId: modelId)
            .filter { $0.artifactId != active.artifactId && $0.status != .failed }
            .sorted { $0.installedAt < $1.installedAt }

        guard let rollbackTarget = allRecords.last else {
            logger.warning("No rollback target available for \(modelId)")
            return false
        }

        // Mark current as rolled back
        var updatedActive = active
        updatedActive.status = .rolledBack
        metadataStore.upsert(updatedActive)

        // Activate rollback target
        metadataStore.activate(artifactId: rollbackTarget.artifactId)
        logger.info("Rolled back \(modelId) to artifact \(rollbackTarget.artifactId)")
        return true
    }

    /// Records a crash for the currently active artifact of a model.
    public func recordCrash(modelId: String) {
        guard let active = metadataStore.activeRecord(forModelId: modelId) else { return }
        metadataStore.incrementCrashCount(artifactId: active.artifactId)
    }

    // MARK: - Internal

    /// Compares desired state against local metadata and returns planned actions.
    internal func planActions(desired: DesiredStateResponse) -> [ReconcileAction] {
        var actions: [ReconcileAction] = []

        for entry in desired.models {
            let artifactId = entry.artifactManifest?.artifactId ?? ""
            guard !artifactId.isEmpty else { continue }

            let existing = metadataStore.record(forArtifactId: artifactId)

            if let existing = existing {
                if existing.artifactVersion == entry.desiredVersion {
                    // Re-download if files were purged from disk
                    let pathExists = FileManager.default.fileExists(atPath: existing.filePath)
                    if !pathExists {
                        actions.append(.download(entry))
                    } else if existing.status == .active {
                        actions.append(.upToDate(modelId: entry.modelId))
                    } else if existing.status == .staged {
                        if entry.activationPolicy == "immediate" {
                            actions.append(.activate(
                                modelId: entry.modelId,
                                version: entry.desiredVersion
                            ))
                        } else {
                            actions.append(.upToDate(modelId: entry.modelId))
                        }
                    } else {
                        // Failed or rolled-back — re-download
                        actions.append(.download(entry))
                    }
                } else {
                    // Different version — download new
                    actions.append(.download(entry))
                }
            } else {
                // Not installed — download
                actions.append(.download(entry))
            }
        }

        // GC eligible artifacts
        for artifactId in desired.gcEligibleArtifactIds {
            if metadataStore.record(forArtifactId: artifactId) != nil {
                actions.append(.remove(artifactId: artifactId))
            }
        }

        return actions
    }

    // MARK: - Download & Stage

    private func downloadAndStage(entry: DesiredModelEntry) async throws {
        guard let artifactId = entry.artifactManifest?.artifactId, !artifactId.isEmpty else {
            throw ArtifactReconcileError.invalidDownloadURL("No artifact manifest for \(entry.modelId)")
        }

        logger.info("Downloading artifact \(artifactId) for model \(entry.modelId)")

        // 1. Fetch file manifest from server
        let manifest = try await controlSync.fetchArtifactManifest(artifactId: artifactId)

        // 2. Get presigned download URLs for all files
        let filePaths = manifest.files.map(\.path)
        let urlsResponse = try await controlSync.fetchDownloadUrls(artifactId: artifactId, files: filePaths)
        let urlMap = Dictionary(urlsResponse.urls.map { ($0.path, $0.url) }, uniquingKeysWith: { a, _ in a })

        // 3. Create artifact directory
        let artifactDir = artifactDirectory
            .appendingPathComponent(entry.modelId, isDirectory: true)
            .appendingPathComponent(entry.desiredVersion, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        // 4. Download each file and verify checksums
        var resourceBindings: [String: String] = [:]
        for file in manifest.files {
            guard let urlString = urlMap[file.path], let url = URL(string: urlString) else {
                throw ArtifactReconcileError.invalidDownloadURL(file.path)
            }

            let (data, response) = try await downloadSession.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ArtifactReconcileError.downloadFailed(
                    artifactId: artifactId,
                    reason: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for \(file.path)"
                )
            }

            let hash = SHA256.hash(data: data)
                .compactMap { String(format: "%02x", $0) }
                .joined()
            guard hash == file.sha256 else {
                throw ArtifactReconcileError.checksumMismatch(
                    artifactId: artifactId,
                    expected: file.sha256,
                    actual: hash
                )
            }

            let filename = URL(fileURLWithPath: file.path).lastPathComponent
            let fileDest = artifactDir.appendingPathComponent(filename)
            try data.write(to: fileDest, options: .atomic)

            // Use explicit kind from manifest when available, otherwise infer from filename
            let bindingKey = file.kind ?? Self.inferResourceKind(from: filename)
            resourceBindings[bindingKey] = filename
        }

        // 5. Record as staged (filePath = directory for multi-file models)
        let record = InstalledModelRecord(
            modelId: entry.modelId,
            modelVersion: entry.desiredVersion,
            artifactVersion: entry.desiredVersion,
            artifactId: artifactId,
            status: .staged,
            filePath: artifactDir.path,
            resourceBindings: resourceBindings
        )
        metadataStore.upsert(record)

        logger.info("Staged artifact \(artifactId) (\(manifest.files.count) files) at \(artifactDir.path)")
    }

    // MARK: - Activation

    private func activateArtifact(artifactId: String) throws {
        guard let record = metadataStore.record(forArtifactId: artifactId) else {
            throw ArtifactReconcileError.artifactNotFound(artifactId)
        }

        // Verify the file still exists
        guard FileManager.default.fileExists(atPath: record.filePath) else {
            throw ArtifactReconcileError.artifactFileNotFound(artifactId: artifactId, path: record.filePath)
        }

        metadataStore.activate(artifactId: artifactId)
        logger.info("Activated artifact \(artifactId) for model \(record.modelId)")
    }

    // MARK: - Removal

    private func removeArtifact(artifactId: String) {
        guard let record = metadataStore.record(forArtifactId: artifactId) else { return }

        // Remove file
        try? FileManager.default.removeItem(atPath: record.filePath)

        // Remove parent directories if empty
        let parentDir = URL(fileURLWithPath: record.filePath).deletingLastPathComponent()
        let grandparentDir = parentDir.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parentDir)
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: grandparentDir.path),
           contents.isEmpty {
            try? FileManager.default.removeItem(at: grandparentDir)
        }

        metadataStore.remove(artifactId: artifactId)
        logger.info("Removed artifact \(artifactId)")
    }

    // MARK: - Report Observed State

    /// Builds and reports observed state to the server.
    public func reportCurrentState(deviceId: String) async {
        let allRecords = metadataStore.allRecords()

        let models = allRecords.map { record in
            ObservedModelEntry(
                modelId: record.modelId,
                artifactId: record.artifactId,
                artifactVersion: record.artifactVersion,
                status: record.status.rawValue,
                errorCode: record.status == .failed ? "activation_failed" : nil
            )
        }

        do {
            try await controlSync.reportObservedState(
                deviceId: deviceId,
                models: models
            )
        } catch {
            logger.warning("Failed to report observed state: \(error.localizedDescription)")
        }
    }

    // MARK: - Resource Kind Inference

    /// Infers an ``ArtifactResourceKind`` raw value from a filename.
    ///
    /// Used as a fallback when the server manifest doesn't include an
    /// explicit `kind` field. Maps common filenames/extensions to the
    /// canonical resource kinds expected by ``ModelRuntimeRegistry``.
    static func inferResourceKind(from filename: String) -> String {
        let lower = filename.lowercased()

        // Exact filename matches
        if lower.hasSuffix("tokenizer.json") || lower.hasSuffix("tokenizer.model") {
            return ArtifactResourceKind.tokenizer.rawValue
        }
        if lower.hasSuffix("tokenizer_config.json") {
            return ArtifactResourceKind.tokenizerConfig.rawValue
        }
        if lower.hasSuffix("config.json") || lower.hasSuffix("model_config.json") {
            return ArtifactResourceKind.modelConfig.rawValue
        }
        if lower.hasSuffix("generation_config.json") {
            return ArtifactResourceKind.generationConfig.rawValue
        }
        if lower.hasSuffix("vocab.json") || lower.hasSuffix("vocab.txt") {
            return ArtifactResourceKind.vocab.rawValue
        }
        if lower.hasSuffix("merges.txt") {
            return ArtifactResourceKind.merges.rawValue
        }
        if lower.hasSuffix("projector") || lower.contains("projector") {
            return ArtifactResourceKind.projector.rawValue
        }

        // Extension-based inference for model weights
        let weightExtensions = ["gguf", "bin", "mlmodelc", "mlpackage", "tflite",
                                "onnx", "mnn", "safetensors", "pt", "pte"]
        let ext = (lower as NSString).pathExtension
        if weightExtensions.contains(ext) {
            return ArtifactResourceKind.weights.rawValue
        }

        // Default: use the filename stem as kind
        return (filename as NSString).deletingPathExtension
    }
}

// MARK: - Errors

/// Errors that can occur during artifact reconciliation.
public enum ArtifactReconcileError: Error, Sendable {
    case invalidDownloadURL(String)
    case downloadFailed(artifactId: String, reason: String)
    case checksumMismatch(artifactId: String, expected: String, actual: String)
    case artifactNotFound(String)
    case artifactFileNotFound(artifactId: String, path: String)
}

extension ArtifactReconcileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDownloadURL(let url):
            return "Invalid download URL: \(url)"
        case .downloadFailed(let id, let reason):
            return "Download failed for artifact \(id): \(reason)"
        case .checksumMismatch(let id, let expected, let actual):
            return "Checksum mismatch for artifact \(id): expected \(expected), got \(actual)"
        case .artifactNotFound(let id):
            return "Artifact not found: \(id)"
        case .artifactFileNotFound(let id, let path):
            return "Artifact file not found for \(id) at path: \(path)"
        }
    }
}

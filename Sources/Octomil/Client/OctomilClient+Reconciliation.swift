import Foundation

// MARK: - Artifact Reconciliation & Installed Models

extension OctomilClient {

    /// Sets up artifact reconciliation for automatic model recovery and desired-state sync.
    ///
    /// Creates an ``ArtifactReconciler``, configures ``BackgroundSync`` for ongoing
    /// background sync (iOS only), and runs an immediate foreground reconcile to
    /// recover any model files that were purged from disk.
    internal func setupArtifactReconciler(deviceId: String) async {
        let controlSync = self.control
        let metadataStore = ModelMetadataStore()
        self.modelMetadataStore = metadataStore
        let reconciler = ArtifactReconciler(
            controlSync: controlSync,
            metadataStore: metadataStore
        )
        self.artifactReconciler = reconciler

        #if os(iOS)
        // Configure background sync for ongoing reconciliation
        BackgroundSync.shared.configureReconciler(
            reconciler: reconciler,
            deviceId: deviceId
        )
        #endif

        // Trigger immediate foreground reconcile to recover any missing models
        do {
            let actions = try await reconciler.reconcile(deviceId: deviceId)
            let meaningful = actions.filter {
                if case .upToDate = $0 { return false }
                return true
            }
            if !meaningful.isEmpty {
                logger.info("Auto-recovery reconcile: \(meaningful.count) action(s)")
            }
        } catch {
            logger.warning("Auto-recovery reconcile failed: \(error.localizedDescription)")
        }

        // Activate any staged next-launch artifacts
        await reconciler.activateNextLaunchArtifacts()

        #if os(iOS)
        // Schedule periodic background sync
        BackgroundSync.shared.scheduleSync()
        #endif
    }

    // MARK: - Installed Models

    /// Returns installed model records that are locally available (active or staged).
    ///
    /// Includes both `.active` and `.staged` records so the host app can bridge
    /// paths for models that were recovered but not yet activated.
    /// Returns an empty array if the metadata store hasn't been initialized yet
    /// (e.g., before device registration).
    public func installedModels() -> [InstalledModelRecord] {
        guard let store = modelMetadataStore else { return [] }
        return store.allRecords().filter { $0.status == .active || $0.status == .staged }
    }

    /// Returns all installed model records (any status) from the SDK metadata store.
    public func allInstalledModels() -> [InstalledModelRecord] {
        guard let store = modelMetadataStore else { return [] }
        return store.allRecords()
    }

    /// Runs a reconciliation cycle: fetches desired state from the server,
    /// downloads missing artifacts, and activates them.
    ///
    /// This is the primary recovery mechanism — call it when models appear
    /// missing on disk. The reconciler compares server-authoritative desired
    /// state against local metadata and downloads/activates as needed.
    ///
    /// - Throws: ``OctomilError/deviceNotRegistered`` if the device hasn't been registered.
    public func recoverModels() async throws {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }
        guard let reconciler = artifactReconciler else {
            // Reconciler not set up yet — create one on the fly
            await setupArtifactReconciler(deviceId: deviceId)
            return
        }
        try await reconciler.reconcile(deviceId: deviceId)
    }
}

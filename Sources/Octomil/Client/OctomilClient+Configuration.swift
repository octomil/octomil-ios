import Foundation

// MARK: - Manifest Configuration

extension OctomilClient {

    /// Configure the SDK with an app manifest.
    ///
    /// Bootstraps all declared models: bundled models are loaded from the
    /// app bundle, managed models are queued for download, and cloud models
    /// are registered immediately.
    ///
    /// ```swift
    /// let manifest = AppManifest(models: [
    ///     AppModelEntry(id: "phi-4-mini", capability: .chat, delivery: .managed),
    ///     AppModelEntry(id: "whisper-base", capability: .transcription, delivery: .bundled,
    ///                   bundledPath: "Models/whisper-base.mlmodelc"),
    /// ])
    /// try await client.configure(manifest: manifest)
    /// ```
    ///
    /// - Parameter manifest: The app manifest.
    public func configure(manifest: AppManifest) async throws {
        let readinessManager = ModelReadinessManager(modelManager: modelManager)
        self.readiness = readinessManager

        let serverURLString = OctomilClient.defaultServerURL.absoluteString
        let apiKey = self.orgId
        let catalogService = ModelCatalogService(
            manifest: manifest,
            modelManager: modelManager,
            readiness: readinessManager,
            cloudRuntimeFactory: { modelId in
                CloudModelRuntime(
                    serverURL: serverURLString,
                    apiKey: apiKey,
                    model: modelId
                )
            }
        )
        self.catalog = catalogService

        // Build capability → model ID mapping for synchronous lookups
        for entry in manifest.models {
            capabilityModelIds[entry.capability] = entry.id
        }

        try await catalogService.bootstrap()

        // Wire catalog resolution into the Response API
        responses.catalogResolver = { [weak self] ref in
            self?.resolveRuntime(ref)
        }

        if configuration.enableLogging {
            logger.info("Manifest configured with \(manifest.models.count) model(s)")
        }
    }

    /// Configure the SDK with manifest, auth, and monitoring.
    ///
    /// This is the preferred entry point for mobile apps. It:
    /// 1. Creates a stable installation ID (random UUID, NOT IDFV)
    /// 2. Creates ``DeviceContext`` immediately
    /// 3. Sets up telemetry resource context
    /// 4. Bootstraps the model catalog
    /// 5. Launches background silent registration if needed
    ///
    /// - Parameters:
    ///   - manifest: App manifest declaring models and capabilities.
    ///   - auth: Optional auth configuration. Nil means local-only.
    ///   - monitoring: Monitoring configuration (heartbeats, health).
    public func configure(
        manifest: AppManifest,
        auth: AuthConfig? = nil,
        monitoring: MonitoringConfig = .disabled
    ) async throws {
        // 1. Generate or load stable installation ID (random UUID, NOT IDFV)
        let installationId = DeviceContext.getOrCreateInstallationId(storage: secureStorage)
        self.clientDeviceIdentifier = installationId

        // 2. Create DeviceContext immediately
        let orgIdValue: String? = auth.flatMap { config in
            let id = config.orgId
            return id.isEmpty ? nil : id
        }
        let appId = Bundle.main.bundleIdentifier
        let context = DeviceContext(
            installationId: installationId,
            orgId: orgIdValue,
            appId: appId
        )
        self.deviceContext = context

        // Wire DeviceContext into Response API for cloud fallback auth
        responses.deviceContext = context

        // 3. Set up telemetry resource context
        TelemetryQueue.shared?.setResourceContext(
            deviceId: installationId,
            orgId: orgIdValue ?? "unknown"
        )

        // 4. Bootstrap catalog (existing logic)
        try await configure(manifest: manifest)

        // 5. Check auto-registration gate and launch background task
        let shouldAutoRegister = auth != nil && (
            manifest.models.contains { $0.delivery == .managed || $0.delivery == .cloud }
            || monitoring.enabled
        )

        if shouldAutoRegister {
            registrationTask = Task { [weak self] in
                await self?.silentRegister()
            }
        } else if let existingDeviceId = self.deviceId {
            // Device already registered from a previous session — set up reconciler
            // immediately without re-registering.
            Task { [weak self] in
                await self?.setupArtifactReconciler(deviceId: existingDeviceId)
            }
        }

        // 6. Start heartbeat if monitoring is enabled
        if monitoring.enabled {
            startHeartbeat()
        }

        if configuration.enableLogging {
            logger.info("Configured with installationId=\(installationId), autoRegister=\(shouldAutoRegister)")
        }
    }

    /// Resolve a ``ModelRuntime`` from a ``ModelRef``.
    ///
    /// Resolution order:
    /// 1. Capability → model ID via manifest mapping → ModelRuntimeRegistry
    /// 2. Model ID → ModelRuntimeRegistry
    internal func resolveRuntime(_ ref: ModelRef) -> ModelRuntime? {
        switch ref {
        case .id(let modelId):
            return ModelRuntimeRegistry.shared.resolve(modelId: modelId)
        case .capability(let cap):
            // Look up the model ID mapped for this capability in the manifest
            if let modelId = capabilityModelIds[cap] {
                return ModelRuntimeRegistry.shared.resolve(modelId: modelId)
            }
            return nil
        }
    }
}

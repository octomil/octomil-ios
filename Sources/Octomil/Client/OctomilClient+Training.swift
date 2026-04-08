import Foundation
import CoreML

// MARK: - Training

extension OctomilClient {

    // MARK: - Unified Training

    /// Train the model on local data with a single, unified API.
    ///
    /// This is the **recommended** way to do all training. It replaces the
    /// previous split between ``joinRound`` and ``trainLocal``.
    ///
    /// ## Upload behavior
    ///
    /// The `uploadPolicy` parameter controls what happens after training:
    /// - ``UploadPolicy/auto``: Extracts weights and uploads automatically.
    ///   Uses SecAgg if enabled and a `roundId` is provided.
    /// - ``UploadPolicy/manual``: Extracts weights but does NOT upload.
    ///   Returns them in ``TrainingOutcome/weightUpdate`` for you to handle.
    /// - ``UploadPolicy/disabled``: No weight extraction or upload. Pure local training.
    ///
    /// ## Degraded mode
    ///
    /// If the model lacks CoreML updatable parameters, behavior depends on
    /// ``OctomilConfiguration/allowDegradedTraining``:
    /// - **false (default)**: Throws ``MissingTrainingSignatureError``.
    /// - **true**: Runs forward-pass training (no weight updates) and sets
    ///   ``TrainingOutcome/degraded`` to `true`.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - trainingConfig: Training configuration.
    ///   - uploadPolicy: Controls weight extraction and upload.
    ///   - roundId: Optional federated learning round ID.
    /// - Returns: ``TrainingOutcome`` with training metrics, optional weights, and upload status.
    /// - Throws: ``MissingTrainingSignatureError`` if model lacks training support and degraded mode is disabled.
    public func train(
        model: OctomilModel,
        dataProvider: @escaping () -> MLBatchProvider,
        trainingConfig: TrainingConfig = .standard,
        uploadPolicy: UploadPolicy = .auto,
        roundId: String? = nil
    ) async throws -> TrainingOutcome {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        // Check for training signature support
        let isDegraded = !model.supportsTraining
        if isDegraded && !configuration.allowDegradedTraining {
            throw MissingTrainingSignatureError(
                availableSignatures: Array(model.inputDescriptions.keys)
            )
        }

        if isDegraded, configuration.enableLogging {
            logger.error("MODEL TRAINING DEGRADED: Model lacks updatable parameters. Weights will NOT be updated on-device.")
        }

        if configuration.enableLogging {
            logger.info("Starting training: policy=\(uploadPolicy.rawValue), round=\(roundId ?? "none"), degraded=\(isDegraded)")
        }

        // Record training started telemetry
        TelemetryQueue.shared?.reportTrainingStarted(
            modelId: model.id,
            version: model.version,
            roundId: roundId ?? "local",
            numSamples: 0
        )
        let trainingStart = CFAbsoluteTimeGetCurrent()

        // Train locally
        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult: TrainingResult

        do {
            if isDegraded {
                // Degraded mode: run inference on training data to collect metrics
                let data = dataProvider()
                let startTime = Date()
                // Run a single prediction to measure forward-pass metrics
                if data.count > 0 {
                    let firstFeature = data.features(at: 0)
                    _ = try? model.predict(input: firstFeature)
                }
                let trainingTime = Date().timeIntervalSince(startTime)
                trainingResult = TrainingResult(
                    sampleCount: data.count,
                    loss: nil,
                    accuracy: nil,
                    trainingTime: trainingTime,
                    metrics: ["training_method": 0.0, "degraded": 1.0]
                )
            } else {
                trainingResult = try await trainer.train(
                    model: model,
                    dataProvider: dataProvider,
                    config: trainingConfig
                )
            }
        } catch {
            // Record training failed telemetry
            let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Handle weight extraction and upload based on policy
        var weightUpdate: WeightUpdate? = nil
        var uploaded = false
        var usedSecAgg = false

        do {
            switch uploadPolicy {
            case .auto:
                if !isDegraded {
                    weightUpdate = try await trainer.extractWeightUpdate(
                        model: model,
                        trainingResult: trainingResult
                    )
                    var update = weightUpdate!
                    update = WeightUpdate(
                        modelId: update.modelId,
                        version: update.version,
                        deviceId: deviceId,
                        weightsData: update.weightsData,
                        sampleCount: update.sampleCount,
                        metrics: update.metrics,
                        dpMetadata: update.dpMetadata
                    )
                    weightUpdate = update

                    // Use SecAgg if available and round-based
                    if let roundId = roundId, secAggClient != nil {
                        usedSecAgg = true
                        try await uploadWithSecAgg(
                            weightUpdate: update,
                            roundId: roundId,
                            deviceId: deviceId
                        )
                        uploaded = true
                    } else {
                        try await apiClient.uploadWeights(update)
                        uploaded = true
                    }
                }

            case .manual:
                if !isDegraded {
                    weightUpdate = try await trainer.extractWeightUpdate(
                        model: model,
                        trainingResult: trainingResult
                    )
                }

            case .disabled:
                break
            }
        } catch {
            // Record training failed telemetry (upload phase)
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Record training completed telemetry
        let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
        TelemetryQueue.shared?.reportTrainingCompleted(
            modelId: model.id,
            version: model.version,
            durationMs: trainingDurationMs,
            loss: trainingResult.loss ?? 0.0,
            accuracy: trainingResult.accuracy ?? 0.0
        )

        // Record weight upload telemetry if weights were uploaded
        if uploaded, let weightUpdate = weightUpdate {
            TelemetryQueue.shared?.reportWeightUpload(
                modelId: model.id,
                roundId: roundId ?? "local",
                sampleCount: weightUpdate.sampleCount
            )
        }

        let outcome = TrainingOutcome(
            trainingResult: trainingResult,
            weightUpdate: weightUpdate,
            uploaded: uploaded,
            secureAggregation: usedSecAgg,
            uploadPolicy: uploadPolicy,
            degraded: isDegraded
        )

        if configuration.enableLogging {
            logger.info("Training complete: \(trainingResult.sampleCount) samples, policy=\(uploadPolicy.rawValue), uploaded=\(uploaded), degraded=\(isDegraded)")
        }

        return outcome
    }

    /// Uploads weight updates using secure aggregation.
    internal func uploadWithSecAgg(
        weightUpdate: WeightUpdate,
        roundId: String,
        deviceId: String
    ) async throws {
        if secAggClient == nil {
            secAggClient = SecureAggregationClient()
        }
        let secAgg = secAggClient!

        let session = try await apiClient.joinSecAggSession(deviceId: deviceId, roundId: roundId)

        let secAggConfig = SecAggConfiguration(
            threshold: session.threshold,
            totalClients: session.totalClients,
            privacyBudget: session.privacyBudget,
            keyLength: session.keyLength
        )

        await secAgg.beginSession(
            sessionId: session.sessionId,
            clientIndex: session.clientIndex,
            configuration: secAggConfig
        )

        let sharesData = try await secAgg.generateKeyShares()
        let shareKeysRequest = SecAggShareKeysRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            sharesData: sharesData.base64EncodedString()
        )
        try await apiClient.submitSecAggShares(shareKeysRequest)

        let maskedWeights = try await secAgg.maskModelUpdate(weightUpdate.weightsData)
        let maskedInputRequest = SecAggMaskedInputRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            maskedWeightsData: maskedWeights.base64EncodedString(),
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics
        )
        try await apiClient.submitSecAggMaskedInput(maskedInputRequest)

        let unmaskInfo = try await apiClient.getSecAggUnmaskInfo(
            sessionId: session.sessionId,
            deviceId: deviceId
        )

        if unmaskInfo.unmaskingRequired {
            let unmaskData = try await secAgg.provideUnmaskingShares(
                droppedClientIndices: unmaskInfo.droppedClientIndices
            )
            let unmaskRequest = SecAggUnmaskRequest(
                sessionId: session.sessionId,
                deviceId: deviceId,
                unmaskData: unmaskData.base64EncodedString()
            )
            try await apiClient.submitSecAggUnmask(unmaskRequest)
        }

        await secAgg.reset()
    }

    // MARK: - Legacy Training

    /// Participates in a federated training round.
    ///
    /// This method:
    /// 1. Downloads the latest model if needed
    /// 2. Trains the model on local data
    /// 3. Extracts weight updates
    /// 4. Uploads updates to the server
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Result of the training round.
    /// - Throws: `OctomilError` if training fails.
    public func joinRound(
        modelId: String,
        dataProvider: @escaping () -> MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Joining training round for model: \(modelId)")
        }

        // Get or download model
        let model: OctomilModel
        if let cached = getCachedModel(modelId: modelId) {
            // Check for updates
            if let updateInfo = try? await checkForUpdates(modelId: modelId), updateInfo.isRequired {
                model = try await downloadModel(modelId: modelId, version: updateInfo.newVersion)
            } else {
                model = cached
            }
        } else {
            model = try await downloadModel(modelId: modelId)
        }

        // Record training started telemetry
        let participateRoundId = UUID().uuidString
        TelemetryQueue.shared?.reportTrainingStarted(
            modelId: model.id,
            version: model.version,
            roundId: participateRoundId,
            numSamples: 0
        )
        let trainingStart = CFAbsoluteTimeGetCurrent()

        // Train locally
        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult: TrainingResult
        do {
            trainingResult = try await trainer.train(
                model: model,
                dataProvider: dataProvider,
                config: config
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Extract and upload weights
        do {
            var weightUpdate = try await trainer.extractWeightUpdate(
                model: model,
                trainingResult: trainingResult
            )
            weightUpdate = WeightUpdate(
                modelId: weightUpdate.modelId,
                version: weightUpdate.version,
                deviceId: deviceId,
                weightsData: weightUpdate.weightsData,
                sampleCount: weightUpdate.sampleCount,
                metrics: weightUpdate.metrics
            )

            try await apiClient.uploadWeights(weightUpdate)

            // Record weight upload telemetry
            TelemetryQueue.shared?.reportWeightUpload(
                modelId: model.id,
                roundId: participateRoundId,
                sampleCount: weightUpdate.sampleCount
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: model.id,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Record training completed telemetry
        let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
        TelemetryQueue.shared?.reportTrainingCompleted(
            modelId: model.id,
            version: model.version,
            durationMs: trainingDurationMs,
            loss: trainingResult.loss ?? 0.0,
            accuracy: trainingResult.accuracy ?? 0.0
        )

        let roundResult = RoundResult(
            roundId: participateRoundId,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            logger.info("Training round completed: \(trainingResult.sampleCount) samples")
        }

        return roundResult
    }

    /// Participates in a federated training round with secure aggregation.
    ///
    /// The client never sends raw gradients to the server. Instead:
    /// 1. Joins a SecAgg session for the round
    /// 2. Generates and distributes Shamir secret shares of a mask seed
    /// 3. Trains locally and masks the weight update before uploading
    /// 4. Participates in unmasking so the server can reconstruct the aggregate
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - roundId: Server-assigned round identifier.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Result of the training round.
    /// - Throws: `OctomilError` if training or SecAgg protocol fails.
    public func joinSecureRound(
        modelId: String,
        roundId: String,
        dataProvider: @escaping () -> MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw OctomilError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Joining SecAgg round \(roundId) for model \(modelId)")
        }

        // Lazily create SecAgg client
        if secAggClient == nil {
            secAggClient = SecureAggregationClient()
        }
        let secAgg = secAggClient!

        // Phase 0: Join the SecAgg session
        let session = try await apiClient.joinSecAggSession(deviceId: deviceId, roundId: roundId)

        let secAggConfig = SecAggConfiguration(
            threshold: session.threshold,
            totalClients: session.totalClients,
            privacyBudget: session.privacyBudget,
            keyLength: session.keyLength
        )

        await secAgg.beginSession(
            sessionId: session.sessionId,
            clientIndex: session.clientIndex,
            configuration: secAggConfig
        )

        // Phase 1: Generate and submit key shares
        let sharesData = try await secAgg.generateKeyShares()
        let shareKeysRequest = SecAggShareKeysRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            sharesData: sharesData.base64EncodedString()
        )
        try await apiClient.submitSecAggShares(shareKeysRequest)

        // Train locally (same as non-SecAgg path)
        let model: OctomilModel
        if let cached = getCachedModel(modelId: modelId) {
            model = cached
        } else {
            model = try await downloadModel(modelId: modelId)
        }

        // Record training started telemetry
        TelemetryQueue.shared?.reportTrainingStarted(
            modelId: modelId,
            version: model.version,
            roundId: roundId,
            numSamples: 0
        )
        let trainingStart = CFAbsoluteTimeGetCurrent()

        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult: TrainingResult
        do {
            trainingResult = try await trainer.train(
                model: model,
                dataProvider: dataProvider,
                config: config
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: modelId,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        let weightUpdate: WeightUpdate
        do {
            weightUpdate = try await trainer.extractWeightUpdate(
                model: model,
                trainingResult: trainingResult
            )
        } catch {
            TelemetryQueue.shared?.reportTrainingFailed(
                modelId: modelId,
                version: model.version,
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        // Phase 2: Mask and submit the model update
        let maskedWeights = try await secAgg.maskModelUpdate(weightUpdate.weightsData)

        let maskedInputRequest = SecAggMaskedInputRequest(
            sessionId: session.sessionId,
            deviceId: deviceId,
            maskedWeightsData: maskedWeights.base64EncodedString(),
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics
        )
        try await apiClient.submitSecAggMaskedInput(maskedInputRequest)

        // Record weight upload telemetry
        TelemetryQueue.shared?.reportWeightUpload(
            modelId: modelId,
            roundId: roundId,
            sampleCount: weightUpdate.sampleCount
        )

        // Phase 3: Unmasking
        let unmaskInfo = try await apiClient.getSecAggUnmaskInfo(
            sessionId: session.sessionId,
            deviceId: deviceId
        )

        if unmaskInfo.unmaskingRequired {
            let unmaskData = try await secAgg.provideUnmaskingShares(
                droppedClientIndices: unmaskInfo.droppedClientIndices
            )
            let unmaskRequest = SecAggUnmaskRequest(
                sessionId: session.sessionId,
                deviceId: deviceId,
                unmaskData: unmaskData.base64EncodedString()
            )
            try await apiClient.submitSecAggUnmask(unmaskRequest)
        }

        await secAgg.reset()

        // Record training completed telemetry
        let trainingDurationMs = (CFAbsoluteTimeGetCurrent() - trainingStart) * 1000
        TelemetryQueue.shared?.reportTrainingCompleted(
            modelId: modelId,
            version: model.version,
            durationMs: trainingDurationMs,
            loss: trainingResult.loss ?? 0.0,
            accuracy: trainingResult.accuracy ?? 0.0
        )

        let roundResult = RoundResult(
            roundId: roundId,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            logger.info("SecAgg round \(roundId) completed: \(trainingResult.sampleCount) samples")
        }

        return roundResult
    }

    /// Trains a model locally without uploading weights.
    ///
    /// Useful for testing and validation.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - data: Training data provider.
    ///   - config: Training configuration.
    /// - Returns: Training result.
    /// - Throws: `OctomilError` if training fails.
    public func trainLocal(
        model: OctomilModel,
        data: MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> TrainingResult {
        let trainer = FederatedTrainer(configuration: configuration)
        return try await trainer.train(
            model: model,
            dataProvider: { data },
            config: config
        )
    }
}

#if os(iOS)
import Foundation
import BackgroundTasks
import os.log
import CoreML

/// Manages background training operations using BackgroundTasks framework.
public final class BackgroundSync: @unchecked Sendable {

    // MARK: - Constants

    /// Background task identifier for training.
    public static let trainingTaskIdentifier = "ai.octomil.training"

    /// Background task identifier for model sync.
    public static let syncTaskIdentifier = "ai.octomil.sync"

    // MARK: - Shared Instance

    /// Shared instance for background operations.
    public static let shared = BackgroundSync()

    // MARK: - Properties

    private let logger: Logger
    private var modelId: String?
    private var dataProvider: (@Sendable () -> MLBatchProvider)?
    private var constraints: BackgroundConstraints?
    private weak var client: OctomilClient?
    private var isConfigured = false
    private let lock = NSLock()

    /// The artifact reconciler for desired-state sync.
    private var reconciler: ArtifactReconciler?
    /// The device ID used for desired-state operations.
    private var deviceId: String?

    // MARK: - Initialization

    private init() {
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "BackgroundSync")
    }

    // MARK: - Registration

    /// Registers background tasks with the system.
    ///
    /// Call this method in your `application(_:didFinishLaunchingWithOptions:)`.
    public static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: trainingTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            shared.handleTrainingTask(processingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: syncTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            shared.handleSyncTask(refreshTask)
        }
    }

    // MARK: - Configuration

    /// Configures background training.
    ///
    /// - Parameters:
    ///   - modelId: Model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - constraints: Background execution constraints.
    ///   - client: Octomil client instance.
    internal func configure(
        modelId: String,
        dataProvider: @escaping @Sendable () -> MLBatchProvider,
        constraints: BackgroundConstraints,
        client: OctomilClient
    ) {
        lock.lock()
        defer { lock.unlock() }

        self.modelId = modelId
        self.dataProvider = dataProvider
        self.constraints = constraints
        self.client = client
        self.isConfigured = true
    }

    /// Configures the reconciler for desired-state sync.
    ///
    /// - Parameters:
    ///   - reconciler: The artifact reconciler to use.
    ///   - deviceId: The server-assigned device ID.
    internal func configureReconciler(
        reconciler: ArtifactReconciler,
        deviceId: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.reconciler = reconciler
        self.deviceId = deviceId
    }

    // MARK: - Scheduling

    /// Schedules the next background training opportunity.
    public func scheduleNextTraining() {
        lock.lock()
        guard isConfigured, let constraints = constraints else {
            lock.unlock()
            return
        }
        lock.unlock()

        let request = BGProcessingTaskRequest(identifier: Self.trainingTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = constraints.requiresCharging

        // Schedule for at least 1 hour from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background training task")
        } catch {
            logger.error("Failed to schedule training: \(error.localizedDescription)")
        }
    }

    /// Schedules a model sync task.
    public func scheduleSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.syncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 900) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled sync task")
        } catch {
            logger.error("Failed to schedule sync: \(error.localizedDescription)")
        }
    }

    /// Cancels all scheduled training tasks.
    public func cancelScheduledTraining() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.trainingTaskIdentifier)
        logger.info("Cancelled scheduled training tasks")
    }

    // MARK: - Task Handlers

    private func handleTrainingTask(_ task: BGProcessingTask) {
        logger.info("Starting background training task")

        // Schedule next training before starting
        scheduleNextTraining()

        // Snapshot state under the lock before entering async context
        lock.lock()
        guard let modelId = modelId,
              let dataProvider = dataProvider,
              let client = client else {
            lock.unlock()
            task.setTaskCompleted(success: false)
            return
        }
        lock.unlock()

        // Create training task
        let trainingTask = Task {
            do {
                let result = try await client.joinRound(
                    modelId: modelId,
                    dataProvider: dataProvider
                )

                logger.info("Background training completed: \(result.trainingResult.sampleCount) samples")
                task.setTaskCompleted(success: true)

            } catch {
                logger.error("Background training failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }

        // Set expiration handler
        task.expirationHandler = {
            trainingTask.cancel()
            self.logger.warning("Background training task expired")
        }
    }

    private func handleSyncTask(_ task: BGAppRefreshTask) {
        logger.debug("Starting background sync task")

        // Schedule next sync
        scheduleSync()

        // Snapshot state under the lock before entering async context
        lock.lock()
        let reconciler = self.reconciler
        let deviceId = self.deviceId
        lock.unlock()

        guard let reconciler = reconciler, let deviceId = deviceId else {
            logger.warning("Reconciler not configured, skipping sync")
            task.setTaskCompleted(success: false)
            return
        }

        let syncTask = Task {
            do {
                let actions = try await reconciler.reconcile(deviceId: deviceId)
                logger.info("Background reconcile completed: \(actions.count) actions")
                task.setTaskCompleted(success: true)
            } catch {
                logger.error("Background sync failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    // MARK: - Status

    /// Checks if background training is configured.
    public var isBackgroundTrainingEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isConfigured && modelId != nil
    }

    /// Checks if background reconcile sync is configured.
    public var isReconcileEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reconciler != nil && deviceId != nil
    }

    /// Gets the configured model ID.
    public var configuredModelId: String? {
        lock.lock()
        defer { lock.unlock() }
        return modelId
    }
}

// MARK: - App Lifecycle Integration

extension BackgroundSync {

    /// Call this when the app enters background.
    public func applicationDidEnterBackground() {
        if isBackgroundTrainingEnabled {
            scheduleNextTraining()
        }
        if isBackgroundTrainingEnabled || isReconcileEnabled {
            scheduleSync()
        }
    }

    /// Call this when the app will terminate.
    public func applicationWillTerminate() {
        // Ensure any pending work is completed
        if isBackgroundTrainingEnabled {
            scheduleNextTraining()
        }
    }
}
#endif

import Foundation
import CoreML
import os.log

/// A deployed model that automatically adapts its compute strategy based on
/// device conditions (battery, thermal, memory, low-power mode).
///
/// `AdaptiveDeployedModel` wraps a CoreML `MLModel` and monitors device state.
/// When conditions change (e.g. thermal pressure increases), it reloads the model
/// with appropriate compute units (ANE -> GPU -> CPU) to balance performance
/// and device health.
///
/// ## Example
/// ```swift
/// let model = try await Deploy.adaptiveModel(from: modelURL)
/// let result = try await model.predict(input: features)
/// print("Using: \(await model.activeComputeUnits)")
/// ```
public actor AdaptiveDeployedModel {

    // MARK: - Properties

    private var model: MLModel
    private let modelURL: URL
    private let stateMonitor: DeviceStateMonitor
    private let loader: AdaptiveModelLoader
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "AdaptiveDeployedModel")

    private var _activeComputeUnits: MLComputeUnits
    private var _isThrottled: Bool = false
    private var _maxConcurrentInferences: Int = 4
    private var _reduceBatchSize: Bool = false
    private var currentInferenceCount: Int = 0
    private var adaptationTask: Task<Void, Never>?

    /// Current compute units being used for inference.
    public var activeComputeUnits: MLComputeUnits {
        _activeComputeUnits
    }

    /// Whether inference is currently throttled due to device conditions.
    public var isThrottled: Bool {
        _isThrottled
    }

    /// Whether batch sizes should be reduced due to device conditions.
    public var reduceBatchSize: Bool {
        _reduceBatchSize
    }

    /// Maximum number of concurrent inferences allowed.
    public var maxConcurrentInferences: Int {
        _maxConcurrentInferences
    }

    // MARK: - Initialization

    /// Creates an adaptive deployed model.
    ///
    /// - Parameters:
    ///   - model: The initially loaded CoreML model.
    ///   - modelURL: URL to the compiled model for reloading.
    ///   - computeUnits: The compute units the model was initially loaded with.
    ///   - stateMonitor: Device state monitor (creates one if nil).
    ///   - loader: Adaptive model loader (creates one if nil).
    public init(
        model: MLModel,
        modelURL: URL,
        computeUnits: MLComputeUnits,
        stateMonitor: DeviceStateMonitor? = nil,
        loader: AdaptiveModelLoader? = nil
    ) {
        self.model = model
        self.modelURL = modelURL
        self._activeComputeUnits = computeUnits
        self.stateMonitor = stateMonitor ?? DeviceStateMonitor()
        self.loader = loader ?? AdaptiveModelLoader()
    }

    deinit {
        adaptationTask?.cancel()
    }

    // MARK: - Public API

    /// Starts the adaptation loop that monitors device state and reloads
    /// the model when conditions change.
    public func startAdaptation() async {
        await stateMonitor.startMonitoring()
        startAdaptationLoop()
    }

    /// Stops the adaptation loop.
    public func stopAdaptation() async {
        adaptationTask?.cancel()
        adaptationTask = nil
        await stateMonitor.stopMonitoring()
    }

    /// Run inference with automatic compute adaptation.
    ///
    /// If inference is throttled, inserts a short delay before executing.
    /// Respects the maximum concurrent inferences limit.
    ///
    /// - Parameter input: CoreML feature provider with model inputs.
    /// - Returns: CoreML feature provider with model outputs.
    /// - Throws: If prediction fails or concurrency limit is exceeded.
    public func predict(input: MLFeatureProvider) async throws -> MLFeatureProvider {
        // Throttle: introduce a short delay to reduce heat/power consumption
        if _isThrottled {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        guard currentInferenceCount < _maxConcurrentInferences else {
            throw AdaptiveModelError.concurrencyLimitReached(
                limit: _maxConcurrentInferences
            )
        }

        currentInferenceCount += 1
        defer { currentInferenceCount -= 1 }

        return try await model.prediction(from: input)
    }

    /// Run inference with a dictionary of inputs.
    ///
    /// - Parameter inputs: Dictionary of feature name to value.
    /// - Returns: CoreML feature provider with model outputs.
    /// - Throws: If prediction fails.
    public func predict(inputs: [String: Any]) async throws -> MLFeatureProvider {
        let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
        return try await predict(input: provider)
    }

    // MARK: - Adaptation Loop

    private func startAdaptationLoop() {
        adaptationTask?.cancel()
        adaptationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.stateMonitor.stateChanges
            for await state in stream {
                guard !Task.isCancelled else { break }
                await self.handleStateChange(state)
            }
        }
    }

    private func handleStateChange(_ state: DeviceStateMonitor.DeviceState) async {
        let recommendation = RuntimeAdapter.recommend(for: state)

        // Update throttle and concurrency settings immediately
        _isThrottled = recommendation.shouldThrottle
        _maxConcurrentInferences = recommendation.maxConcurrentInferences
        _reduceBatchSize = recommendation.reduceBatchSize

        // Only reload model if compute units changed
        guard recommendation.computeUnits != _activeComputeUnits else {
            return
        }

        logger.info("Adapting compute units: \(self.computeUnitsName(self._activeComputeUnits)) -> \(self.computeUnitsName(recommendation.computeUnits)). Reason: \(recommendation.reason)")

        do {
            let newModel = try await loader.reload(
                model: model,
                from: modelURL,
                computeUnits: recommendation.computeUnits
            )
            self.model = newModel
            self._activeComputeUnits = recommendation.computeUnits
        } catch {
            // If reload fails, keep using the current model but log the failure
            logger.error("Failed to reload model with \(self.computeUnitsName(recommendation.computeUnits)): \(error.localizedDescription). Keeping current configuration.")
        }
    }

    private nonisolated func computeUnitsName(_ units: MLComputeUnits) -> String {
        switch units {
        case .all: return "all"
        case .cpuAndGPU: return "cpuAndGPU"
        case .cpuOnly: return "cpuOnly"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Errors

/// Errors specific to adaptive model inference.
public enum AdaptiveModelError: Error, LocalizedError {
    /// Too many concurrent inferences running.
    case concurrencyLimitReached(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .concurrencyLimitReached(let limit):
            return "Concurrency limit reached: maximum \(limit) concurrent inferences allowed under current device conditions."
        }
    }
}

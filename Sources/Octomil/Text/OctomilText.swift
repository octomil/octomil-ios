import Foundation

/// Namespace for text prediction APIs on ``OctomilClient``.
///
/// ```swift
/// // Contract-aligned API:
/// let result = try await client.text.predictions.create(
///     input: "The quick brown",
///     n: 5
/// )
///
/// // Convenience shorthand (backward compatible):
/// let suggestions = try await client.text.predict(prefix: "The quick brown")
/// ```
public final class OctomilText: @unchecked Sendable {

    private let runtimeResolver: (ModelRef) -> ModelRuntime?

    /// Text predictions sub-namespace — matches `text.predictions.create` contract.
    public let predictions: TextPredictions

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.runtimeResolver = runtimeResolver
        self.predictions = TextPredictions(runtimeResolver: runtimeResolver)
    }

    // MARK: - Convenience (backward compatible)

    /// Generate text completion suggestions for the given prefix.
    ///
    /// This is a convenience wrapper around ``TextPredictions/create(model:input:n:)``.
    ///
    /// - Parameters:
    ///   - model: Model reference — by ID or capability.
    ///   - prefix: The text typed so far.
    ///   - maxSuggestions: Maximum suggestions to return (default: 3).
    /// - Returns: An array of completion suggestions.
    public func predict(
        model: ModelRef = .capability(.textCompletion),
        prefix: String,
        maxSuggestions: Int = 3
    ) async throws -> [String] {
        let result = try await predictions.create(
            model: model,
            input: prefix,
            n: maxSuggestions
        )
        return result.predictions.map(\.text)
    }

    // MARK: - Stateful Predictor

    /// Create a stateful predictor that keeps the model warm between calls.
    ///
    /// - Parameter capability: The model capability to use.
    /// - Returns: A ``OctomilPredictor`` instance.
    public func predictor(capability: ModelCapability = .textCompletion) -> OctomilPredictor? {
        guard let runtime = runtimeResolver(.capability(capability)) else { return nil }
        return OctomilPredictor(runtime: runtime, modelId: capability.rawValue)
    }

    /// Create a stateful predictor for a specific model ID.
    ///
    /// - Parameter model: The model reference.
    /// - Returns: A ``OctomilPredictor`` instance.
    public func predictor(model: ModelRef) -> OctomilPredictor? {
        guard let runtime = runtimeResolver(model) else { return nil }
        let id: String
        switch model {
        case .id(let modelId): id = modelId
        case .capability(let cap): id = cap.rawValue
        }
        return OctomilPredictor(runtime: runtime, modelId: id)
    }
}

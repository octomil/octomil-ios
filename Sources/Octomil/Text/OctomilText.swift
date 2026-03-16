import Foundation

/// Namespace for text prediction APIs on ``OctomilClient``.
///
/// ```swift
/// let suggestions = try await client.text.predict(
///     model: .capability(.textCompletion),
///     prefix: "The quick brown"
/// )
/// ```
public final class OctomilText: @unchecked Sendable {

    private let runtimeResolver: (ModelRef) -> ModelRuntime?

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.runtimeResolver = runtimeResolver
    }

    // MARK: - One-shot Prediction

    /// Generate text completion suggestions for the given prefix.
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
        guard let runtime = runtimeResolver(model) else {
            throw OctomilError.runtimeUnavailable(reason: "No runtime for text prediction model")
        }

        let request = RuntimeRequest(
            prompt: prefix,
            maxTokens: 32,
            temperature: 0.3
        )

        let response = try await runtime.run(request: request)

        let raw = response.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Array(raw.prefix(maxSuggestions))
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

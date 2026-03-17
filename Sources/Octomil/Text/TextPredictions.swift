import Foundation

/// Text predictions API — accessed via `client.text.predictions`.
///
/// ```swift
/// let result = try await client.text.predictions.create(
///     input: "The quick brown",
///     n: 5
/// )
/// for candidate in result.predictions {
///     print(candidate.text)
/// }
/// ```
public final class TextPredictions: @unchecked Sendable {

    private let runtimeResolver: (ModelRef) -> ModelRuntime?

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.runtimeResolver = runtimeResolver
    }

    /// Generate text prediction candidates for the given input.
    ///
    /// - Parameters:
    ///   - model: Model reference — by ID or capability.
    ///   - input: The context text to predict from.
    ///   - n: Number of candidates to return (default: 3, max: 20).
    /// - Returns: A ``TextPredictionResult`` containing ranked candidates.
    public func create(
        model: ModelRef = .capability(.textCompletion),
        input: String,
        n: Int = 3
    ) async throws -> TextPredictionResult {
        guard let runtime = runtimeResolver(model) else {
            throw OctomilError.runtimeUnavailable(reason: "No runtime for text prediction model")
        }

        let clampedN = max(1, min(n, 20))
        let start = ContinuousClock.now

        let request = RuntimeRequest(
            prompt: input,
            maxTokens: 32,
            temperature: 0.3
        )

        let response = try await runtime.run(request: request)

        let elapsed = ContinuousClock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        let candidates = response.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(clampedN)
            .map { PredictionCandidate(text: $0) }

        return TextPredictionResult(
            predictions: Array(candidates),
            latencyMs: latencyMs
        )
    }
}

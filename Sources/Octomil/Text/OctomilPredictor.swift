import Foundation

/// Stateful text predictor that keeps the model warm between calls.
///
/// Created via ``OctomilText/predictor(capability:)`` or
/// ``OctomilText/predictor(model:)``.
///
/// ```swift
/// let predictor = client.text.predictor(capability: .textCompletion)
/// let suggestions = try await predictor.predict(prefix: "The quick brown")
/// ```
public final class OctomilPredictor: @unchecked Sendable {

    private let runtime: ModelRuntime
    private let modelId: String

    init(runtime: ModelRuntime, modelId: String) {
        self.runtime = runtime
        self.modelId = modelId
    }

    /// Generate text completions for the given prefix.
    ///
    /// - Parameters:
    ///   - prefix: The text typed so far.
    ///   - maxSuggestions: Maximum number of suggestions to return (default: 3).
    /// - Returns: An array of completion suggestions.
    public func predict(prefix: String, maxSuggestions: Int = 3) async throws -> [String] {
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text(prefix)])],
            generationConfig: GenerationConfig(maxTokens: 32, temperature: 0.3)
        )

        let response = try await runtime.run(request: request)

        // Split the response into individual suggestions.
        // Engines may return newline-delimited completions.
        let raw = response.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Array(raw.prefix(maxSuggestions))
    }

    /// Release the warm model resources.
    public func close() {
        runtime.close()
    }
}

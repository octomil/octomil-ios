import Foundation

// MARK: - PredictionCandidate

/// A single prediction candidate with optional confidence score.
public struct PredictionCandidate: Sendable {
    /// The predicted text (next word or phrase).
    public let text: String
    /// Model output score (0.0–1.0), if available.
    public let score: Double?

    public init(text: String, score: Double? = nil) {
        self.text = text
        self.score = score
    }
}

// MARK: - TextPredictionResult

/// The result of a text prediction request.
///
/// Matches the contract schema `text_prediction_result.json`.
public struct TextPredictionResult: Sendable {
    /// Ranked prediction candidates.
    public let predictions: [PredictionCandidate]
    /// Resolved model ID used for prediction.
    public let model: String?
    /// End-to-end prediction latency in milliseconds.
    public let latencyMs: Int?

    public init(
        predictions: [PredictionCandidate],
        model: String? = nil,
        latencyMs: Int? = nil
    ) {
        self.predictions = predictions
        self.model = model
        self.latencyMs = latencyMs
    }
}

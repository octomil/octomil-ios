#if canImport(SwiftUI)
import Foundation
import CoreML
import os.log

/// The modality that determines which sub-view ``TryItOutScreen`` renders.
///
/// Parsed from the ``PairedModelInfo/modality`` string returned by the server.
/// Unknown or nil values default to ``text``.
@available(iOS 15.0, macOS 12.0, *)
public enum TryItOutModality: String, Sendable, CaseIterable {
    case text
    case vision
    case audio
    case classification

    /// Parses a server-provided modality string into the appropriate case.
    ///
    /// Handles common aliases (e.g. "image" maps to ``vision``).
    /// Returns ``text`` for nil or unrecognized values.
    public static func from(_ raw: String?) -> TryItOutModality {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return .text
        }
        switch raw {
        case "text", "llm", "language":
            return .text
        case "vision", "image", "visual":
            return .vision
        case "audio", "speech", "voice":
            return .audio
        case "classification", "classifier", "classify":
            return .classification
        default:
            return .text
        }
    }
}

/// State of an inference request in the Try It Out flow.
@available(iOS 15.0, macOS 12.0, *)
public enum InferenceState: Sendable {
    /// No inference has been run yet.
    case idle
    /// Inference is currently running.
    case loading
    /// Inference completed successfully.
    case result(output: String, latencyMs: Double)
    /// Inference failed with an error.
    case error(message: String)
}

/// A single message in the chat-style text modality view.
@available(iOS 15.0, macOS 12.0, *)
public struct ChatMessage: Identifiable, Sendable {
    public let id: String
    /// Whether this message is from the user (true) or the model (false).
    public let isUser: Bool
    /// The message text content.
    public let text: String
    /// Inference latency in milliseconds (only set for model responses).
    public let latencyMs: Double?
    /// Timestamp when the message was created.
    public let timestamp: Date

    public init(isUser: Bool, text: String, latencyMs: Double? = nil) {
        self.id = UUID().uuidString
        self.isUser = isUser
        self.text = text
        self.latencyMs = latencyMs
        self.timestamp = Date()
    }
}

/// A single classification result with label and confidence score.
@available(iOS 15.0, macOS 12.0, *)
public struct ClassificationResult: Identifiable, Sendable {
    public let id: String
    /// The predicted class label.
    public let label: String
    /// Confidence score (0.0 to 1.0).
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.id = UUID().uuidString
        self.label = label
        self.confidence = confidence
    }
}

/// View model driving the "Try it out" screen after model deployment.
///
/// Manages inference calls, tracks latency, and publishes state updates
/// that the modality-specific sub-views observe.
@available(iOS 15.0, macOS 12.0, *)
@MainActor
public final class TryItOutViewModel: ObservableObject {

    // MARK: - Published State

    /// The resolved modality for the current model.
    @Published public private(set) var modality: TryItOutModality

    /// Current inference state.
    @Published public private(set) var inferenceState: InferenceState = .idle

    /// Chat messages for the text modality.
    @Published public private(set) var messages: [ChatMessage] = []

    /// Classification results for the classification modality.
    @Published public private(set) var classificationResults: [ClassificationResult] = []

    /// The last inference latency in milliseconds.
    @Published public private(set) var lastLatencyMs: Double?

    // MARK: - Model Info

    /// The paired model info from the pairing flow.
    public let modelInfo: PairedModelInfo

    // MARK: - Private

    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "TryItOutViewModel")
    private var inferenceTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a view model for the Try It Out screen.
    ///
    /// - Parameter modelInfo: Model information from the completed pairing flow.
    public init(modelInfo: PairedModelInfo) {
        self.modelInfo = modelInfo
        self.modality = TryItOutModality.from(modelInfo.modality)
    }

    deinit {
        inferenceTask?.cancel()
    }

    // MARK: - Text Inference

    /// Sends a text prompt to the model and appends the response to the chat.
    ///
    /// - Parameter prompt: The user's text input.
    public func sendTextPrompt(_ prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = ChatMessage(isUser: true, text: prompt)
        messages.append(userMessage)
        inferenceState = .loading

        inferenceTask?.cancel()
        inferenceTask = Task { [weak self] in
            guard let self else { return }
            await self.runTextInference(prompt: prompt)
        }
    }

    // MARK: - Vision Inference

    /// Sends image data with an optional text prompt for vision inference.
    ///
    /// - Parameters:
    ///   - imageData: Raw image data (JPEG or PNG).
    ///   - prompt: Optional text prompt describing what to analyze.
    public func analyzeImage(imageData: Data, prompt: String?) {
        inferenceState = .loading

        inferenceTask?.cancel()
        inferenceTask = Task { [weak self] in
            guard let self else { return }
            await self.runVisionInference(imageData: imageData, prompt: prompt)
        }
    }

    // MARK: - Classification Inference

    /// Classifies an image and produces top-K label results.
    ///
    /// - Parameter imageData: Raw image data (JPEG or PNG).
    public func classifyImage(imageData: Data) {
        inferenceState = .loading
        classificationResults = []

        inferenceTask?.cancel()
        inferenceTask = Task { [weak self] in
            guard let self else { return }
            await self.runClassificationInference(imageData: imageData)
        }
    }

    // MARK: - Audio Inference

    /// Transcribes audio data.
    ///
    /// - Parameter audioData: Raw audio data (WAV, M4A, etc.).
    public func transcribeAudio(audioData: Data) {
        inferenceState = .loading

        inferenceTask?.cancel()
        inferenceTask = Task { [weak self] in
            guard let self else { return }
            await self.runAudioInference(audioData: audioData)
        }
    }

    // MARK: - Reset

    /// Clears all messages, results, and resets to idle state.
    public func reset() {
        inferenceTask?.cancel()
        messages = []
        classificationResults = []
        inferenceState = .idle
        lastLatencyMs = nil
    }

    // MARK: - Private Inference Methods

    private func runTextInference(prompt: String) async {
        let start = CFAbsoluteTimeGetCurrent()

        do {
            // Simulate inference -- in production this would call the model's
            // predictStream or predict method via the deployed model reference.
            try await Task.sleep(nanoseconds: 500_000_000)

            if Task.isCancelled { return }

            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            // Placeholder response -- actual inference integration would
            // replace this with real model output.
            let response = "[Model response for: \(prompt)]"

            let modelMessage = ChatMessage(isUser: false, text: response, latencyMs: latencyMs)
            messages.append(modelMessage)
            lastLatencyMs = latencyMs
            inferenceState = .result(output: response, latencyMs: latencyMs)

            logger.debug("Text inference completed in \(latencyMs, format: .fixed(precision: 1))ms")

        } catch is CancellationError {
            // Task cancelled, no-op
        } catch {
            inferenceState = .error(message: error.localizedDescription)
            logger.error("Text inference failed: \(error.localizedDescription)")
        }
    }

    private func runVisionInference(imageData: Data, prompt: String?) async {
        let start = CFAbsoluteTimeGetCurrent()

        do {
            try await Task.sleep(nanoseconds: 800_000_000)

            if Task.isCancelled { return }

            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            let response = "[Vision analysis result]"
            lastLatencyMs = latencyMs
            inferenceState = .result(output: response, latencyMs: latencyMs)

            logger.debug("Vision inference completed in \(latencyMs, format: .fixed(precision: 1))ms")

        } catch is CancellationError {
            // no-op
        } catch {
            inferenceState = .error(message: error.localizedDescription)
            logger.error("Vision inference failed: \(error.localizedDescription)")
        }
    }

    private func runClassificationInference(imageData: Data) async {
        let start = CFAbsoluteTimeGetCurrent()

        do {
            try await Task.sleep(nanoseconds: 300_000_000)

            if Task.isCancelled { return }

            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            // Placeholder classification results -- real implementation
            // would parse the model's MLFeatureProvider output into labels.
            let results = [
                ClassificationResult(label: "cat", confidence: 0.94),
                ClassificationResult(label: "dog", confidence: 0.04),
                ClassificationResult(label: "bird", confidence: 0.01),
                ClassificationResult(label: "other", confidence: 0.01),
            ]

            classificationResults = results
            lastLatencyMs = latencyMs
            inferenceState = .result(output: "Classification complete", latencyMs: latencyMs)

            logger.debug("Classification inference completed in \(latencyMs, format: .fixed(precision: 1))ms")

        } catch is CancellationError {
            // no-op
        } catch {
            inferenceState = .error(message: error.localizedDescription)
            logger.error("Classification inference failed: \(error.localizedDescription)")
        }
    }

    private func runAudioInference(audioData: Data) async {
        let start = CFAbsoluteTimeGetCurrent()

        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            if Task.isCancelled { return }

            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            let response = "[Transcription result]"
            lastLatencyMs = latencyMs
            inferenceState = .result(output: response, latencyMs: latencyMs)

            logger.debug("Audio inference completed in \(latencyMs, format: .fixed(precision: 1))ms")

        } catch is CancellationError {
            // no-op
        } catch {
            inferenceState = .error(message: error.localizedDescription)
            logger.error("Audio inference failed: \(error.localizedDescription)")
        }
    }
}
#endif

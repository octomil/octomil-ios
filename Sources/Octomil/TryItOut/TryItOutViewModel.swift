#if canImport(SwiftUI)
import Foundation
import CoreML
import os.log
#if canImport(UIKit)
import UIKit
#endif

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

    /// Determines the primary modality from an array of input modalities.
    ///
    /// Returns the highest-priority non-text modality found. If the array
    /// contains only text (or is nil/empty), returns ``text``.
    public static func from(_ modalities: [String]?) -> TryItOutModality {
        guard let modalities, !modalities.isEmpty else { return .text }
        // Return the first non-text modality we recognise.
        for raw in modalities {
            let parsed = from(raw)
            if parsed != .text { return parsed }
        }
        return .text
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
public struct TryItOutMessage: Identifiable, Sendable {
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
/// Loads the on-device model via ``Deploy`` and runs inference through
/// the ``DeployedModel`` API. Falls back to placeholder responses if
/// no compiled model URL is available.
@available(iOS 15.0, macOS 12.0, *)
@MainActor
public final class TryItOutViewModel: ObservableObject {

    // MARK: - Published State

    /// The resolved modality for the current model.
    @Published public private(set) var modality: TryItOutModality

    /// Current inference state.
    @Published public private(set) var inferenceState: InferenceState = .idle

    /// Chat messages for the text modality.
    @Published public private(set) var messages: [TryItOutMessage] = []

    /// Classification results for the classification modality.
    @Published public private(set) var classificationResults: [ClassificationResult] = []

    /// The last inference latency in milliseconds.
    @Published public private(set) var lastLatencyMs: Double?

    /// Whether the on-device model is loaded and ready for inference.
    @Published public private(set) var modelLoaded = false

    // MARK: - Model Info

    /// The paired model info from the pairing flow.
    public let modelInfo: PairedModelInfo

    // MARK: - Private

    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "TryItOutViewModel")
    private var inferenceTask: Task<Void, Never>?
    private var deployedModel: DeployedModel?

    // MARK: - Initialization

    /// Creates a view model for the Try It Out screen.
    ///
    /// - Parameter modelInfo: Model information from the completed pairing flow.
    public init(modelInfo: PairedModelInfo) {
        self.modelInfo = modelInfo
        self.modality = TryItOutModality.from(modelInfo.modalities)
    }

    deinit {
        inferenceTask?.cancel()
    }

    // MARK: - Model Loading

    /// Loads the on-device model. Call this from `.task` in the view.
    public func loadModelIfNeeded() async {
        guard deployedModel == nil, let url = modelInfo.compiledModelURL else { return }
        do {
            deployedModel = try await Deploy.model(at: url, benchmark: false)
            modelLoaded = true
            logger.info("Model loaded: \(self.modelInfo.name)")
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription)")
            inferenceState = .error(message: "Failed to load model: \(error.localizedDescription)")
        }
    }

    // MARK: - Text Inference

    /// Sends a text prompt to the model and appends the response to the chat.
    public func sendTextPrompt(_ prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = TryItOutMessage(isUser: true, text: prompt)
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

    // MARK: - Private Inference

    private func runTextInference(prompt: String) async {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response: String
            if let model = deployedModel {
                let input = try Self.buildInput(for: model.model, textInput: prompt)
                let output = try model.predict(input: input)
                response = Self.formatOutput(output)
            } else {
                response = "[Model not loaded]"
            }
            if Task.isCancelled { return }
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            messages.append(TryItOutMessage(isUser: false, text: response, latencyMs: latencyMs))
            lastLatencyMs = latencyMs
            inferenceState = .result(output: response, latencyMs: latencyMs)
        } catch is CancellationError {
        } catch {
            inferenceState = .error(message: error.localizedDescription)
        }
    }

    private func runVisionInference(imageData: Data, prompt: String?) async {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response: String
            if let model = deployedModel {
                let input = try Self.buildInput(for: model.model, imageData: imageData, textInput: prompt)
                let output = try model.predict(input: input)
                response = Self.formatOutput(output)
            } else {
                response = "[Model not loaded]"
            }
            if Task.isCancelled { return }
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            lastLatencyMs = latencyMs
            inferenceState = .result(output: response, latencyMs: latencyMs)
        } catch is CancellationError {
        } catch {
            inferenceState = .error(message: error.localizedDescription)
        }
    }

    private func runClassificationInference(imageData: Data) async {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            if let model = deployedModel {
                let input = try Self.buildInput(for: model.model, imageData: imageData)
                let output = try model.predict(input: input)
                classificationResults = Self.parseClassification(output)
            } else {
                classificationResults = [ClassificationResult(label: "Model not loaded", confidence: 0)]
            }
            if Task.isCancelled { return }
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            lastLatencyMs = latencyMs
            inferenceState = .result(output: "Classification complete", latencyMs: latencyMs)
        } catch is CancellationError {
        } catch {
            inferenceState = .error(message: error.localizedDescription)
        }
    }

    private func runAudioInference(audioData: Data) async {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response: String
            if let model = deployedModel {
                let input = try Self.buildInput(for: model.model, audioData: audioData)
                let output = try model.predict(input: input)
                response = Self.formatOutput(output)
            } else {
                response = "[Model not loaded]"
            }
            if Task.isCancelled { return }
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            lastLatencyMs = latencyMs
            inferenceState = .result(output: response, latencyMs: latencyMs)
        } catch is CancellationError {
        } catch {
            inferenceState = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Input Building

    /// Builds an MLFeatureProvider matching the model's input spec from the provided data.
    private static func buildInput(
        for model: OctomilModel,
        imageData: Data? = nil,
        textInput: String? = nil,
        audioData: Data? = nil
    ) throws -> MLFeatureProvider {
        let inputDescs = model.mlModel.modelDescription.inputDescriptionsByName
        var features: [String: Any] = [:]

        for (name, desc) in inputDescs {
            if let imageConstraint = desc.imageConstraint, let data = imageData {
                if let pb = pixelBuffer(from: data, width: imageConstraint.pixelsWide, height: imageConstraint.pixelsHigh) {
                    features[name] = pb
                }
            } else if let constraint = desc.multiArrayConstraint {
                let array = try MLMultiArray(shape: constraint.shape, dataType: .float32)
                if let text = textInput {
                    let encoded = Array(text.utf8).map { Float($0) }
                    for i in 0..<min(encoded.count, array.count) {
                        array[i] = NSNumber(value: encoded[i])
                    }
                } else if let audio = audioData {
                    let floats = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    for i in 0..<min(floats.count, array.count) {
                        array[i] = NSNumber(value: floats[i])
                    }
                }
                features[name] = array
            }
        }

        guard !features.isEmpty else {
            throw DeployError.unsupportedFormat("No compatible input features found")
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    // MARK: - Output Formatting

    private static func formatOutput(_ output: MLFeatureProvider) -> String {
        var parts: [String] = []
        for name in output.featureNames {
            guard let value = output.featureValue(for: name) else { continue }
            switch value.type {
            case .string:
                let s = value.stringValue
                if !s.isEmpty { parts.append(s) }
            case .double:
                parts.append(String(format: "%.4f", value.doubleValue))
            case .int64:
                parts.append("\(value.int64Value)")
            case .multiArray:
                if let arr = value.multiArrayValue {
                    let n = min(arr.count, 20)
                    let vals = (0..<n).map { String(format: "%.4f", arr[$0].floatValue) }
                    parts.append("[\(vals.joined(separator: ", "))\(arr.count > 20 ? ", ..." : "")]")
                }
            case .dictionary:
                let dict = value.dictionaryValue
                let entries = dict.sorted { "\($0.key)" < "\($1.key)" }.prefix(10).map { "\($0.key): \($0.value)" }
                parts.append("{\(entries.joined(separator: ", "))}")
            default:
                parts.append("\(name): <\(value.type)>")
            }
        }
        return parts.isEmpty ? "No output" : parts.joined(separator: "\n")
    }

    private static func parseClassification(_ output: MLFeatureProvider) -> [ClassificationResult] {
        for name in output.featureNames {
            if let dict = output.featureValue(for: name)?.dictionaryValue as? [String: Double] {
                return dict.sorted { $0.value > $1.value }.prefix(10).map {
                    ClassificationResult(label: $0.key, confidence: $0.value)
                }
            }
        }
        for name in output.featureNames {
            if let arr = output.featureValue(for: name)?.multiArrayValue {
                return (0..<min(arr.count, 10)).map {
                    ClassificationResult(label: "class_\($0)", confidence: arr[$0].doubleValue)
                }.sorted { $0.confidence > $1.confidence }
            }
        }
        return []
    }

    // MARK: - Image Helpers

    private static func pixelBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
        #else
        return nil
        #endif
    }
}
#endif

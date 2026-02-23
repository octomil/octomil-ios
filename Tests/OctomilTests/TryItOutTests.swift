#if canImport(SwiftUI)
import Combine
import XCTest
@testable import Octomil

// MARK: - TryItOutModality Tests

@available(iOS 15.0, macOS 12.0, *)
final class TryItOutModalityTests: XCTestCase {

    // MARK: - Parsing from server strings

    func testTextModalityFromTextString() {
        XCTAssertEqual(TryItOutModality.from("text"), .text)
    }

    func testTextModalityFromLLMString() {
        XCTAssertEqual(TryItOutModality.from("llm"), .text)
    }

    func testTextModalityFromLanguageString() {
        XCTAssertEqual(TryItOutModality.from("language"), .text)
    }

    func testVisionModalityFromVisionString() {
        XCTAssertEqual(TryItOutModality.from("vision"), .vision)
    }

    func testVisionModalityFromImageString() {
        XCTAssertEqual(TryItOutModality.from("image"), .vision)
    }

    func testVisionModalityFromVisualString() {
        XCTAssertEqual(TryItOutModality.from("visual"), .vision)
    }

    func testAudioModalityFromAudioString() {
        XCTAssertEqual(TryItOutModality.from("audio"), .audio)
    }

    func testAudioModalityFromSpeechString() {
        XCTAssertEqual(TryItOutModality.from("speech"), .audio)
    }

    func testAudioModalityFromVoiceString() {
        XCTAssertEqual(TryItOutModality.from("voice"), .audio)
    }

    func testClassificationModalityFromClassificationString() {
        XCTAssertEqual(TryItOutModality.from("classification"), .classification)
    }

    func testClassificationModalityFromClassifierString() {
        XCTAssertEqual(TryItOutModality.from("classifier"), .classification)
    }

    func testClassificationModalityFromClassifyString() {
        XCTAssertEqual(TryItOutModality.from("classify"), .classification)
    }

    func testNilDefaultsToText() {
        XCTAssertEqual(TryItOutModality.from(nil), .text)
    }

    func testEmptyStringDefaultsToText() {
        XCTAssertEqual(TryItOutModality.from(""), .text)
    }

    func testUnknownStringDefaultsToText() {
        XCTAssertEqual(TryItOutModality.from("unknown_modality"), .text)
    }

    func testCaseInsensitivity() {
        XCTAssertEqual(TryItOutModality.from("TEXT"), .text)
        XCTAssertEqual(TryItOutModality.from("Vision"), .vision)
        XCTAssertEqual(TryItOutModality.from("AUDIO"), .audio)
        XCTAssertEqual(TryItOutModality.from("Classification"), .classification)
    }

    func testWhitespaceHandling() {
        XCTAssertEqual(TryItOutModality.from("  text  "), .text)
        XCTAssertEqual(TryItOutModality.from(" vision "), .vision)
    }

    func testAllCases() {
        let cases = TryItOutModality.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.text))
        XCTAssertTrue(cases.contains(.vision))
        XCTAssertTrue(cases.contains(.audio))
        XCTAssertTrue(cases.contains(.classification))
    }

    func testRawValues() {
        XCTAssertEqual(TryItOutModality.text.rawValue, "text")
        XCTAssertEqual(TryItOutModality.vision.rawValue, "vision")
        XCTAssertEqual(TryItOutModality.audio.rawValue, "audio")
        XCTAssertEqual(TryItOutModality.classification.rawValue, "classification")
    }
}

// MARK: - InferenceState Tests

@available(iOS 15.0, macOS 12.0, *)
final class InferenceStateTests: XCTestCase {

    func testIdleState() {
        let state = InferenceState.idle
        if case .idle = state {
            // pass
        } else {
            XCTFail("Expected idle state")
        }
    }

    func testLoadingState() {
        let state = InferenceState.loading
        if case .loading = state {
            // pass
        } else {
            XCTFail("Expected loading state")
        }
    }

    func testResultState() {
        let state = InferenceState.result(output: "hello", latencyMs: 42.5)
        if case .result(let output, let latency) = state {
            XCTAssertEqual(output, "hello")
            XCTAssertEqual(latency, 42.5, accuracy: 0.01)
        } else {
            XCTFail("Expected result state")
        }
    }

    func testErrorState() {
        let state = InferenceState.error(message: "Something went wrong")
        if case .error(let msg) = state {
            XCTAssertEqual(msg, "Something went wrong")
        } else {
            XCTFail("Expected error state")
        }
    }
}

// MARK: - ChatMessage Tests

@available(iOS 15.0, macOS 12.0, *)
final class ChatMessageTests: XCTestCase {

    func testUserMessage() {
        let msg = ChatMessage(isUser: true, text: "Hello")
        XCTAssertTrue(msg.isUser)
        XCTAssertEqual(msg.text, "Hello")
        XCTAssertNil(msg.latencyMs)
        XCTAssertFalse(msg.id.isEmpty)
    }

    func testModelMessage() {
        let msg = ChatMessage(isUser: false, text: "Response", latencyMs: 123.4)
        XCTAssertFalse(msg.isUser)
        XCTAssertEqual(msg.text, "Response")
        XCTAssertEqual(msg.latencyMs ?? -1, 123.4, accuracy: 0.01)
    }

    func testUniqueIds() {
        let a = ChatMessage(isUser: true, text: "A")
        let b = ChatMessage(isUser: true, text: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testTimestampIsPopulated() {
        let before = Date()
        let msg = ChatMessage(isUser: true, text: "test")
        let after = Date()
        XCTAssertTrue(msg.timestamp >= before)
        XCTAssertTrue(msg.timestamp <= after)
    }
}

// MARK: - ClassificationResult Tests

@available(iOS 15.0, macOS 12.0, *)
final class ClassificationResultTests: XCTestCase {

    func testResultProperties() {
        let result = ClassificationResult(label: "cat", confidence: 0.94)
        XCTAssertEqual(result.label, "cat")
        XCTAssertEqual(result.confidence, 0.94, accuracy: 0.001)
        XCTAssertFalse(result.id.isEmpty)
    }

    func testUniqueIds() {
        let a = ClassificationResult(label: "cat", confidence: 0.9)
        let b = ClassificationResult(label: "cat", confidence: 0.9)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testZeroConfidence() {
        let result = ClassificationResult(label: "unknown", confidence: 0.0)
        XCTAssertEqual(result.confidence, 0.0, accuracy: 0.001)
    }

    func testFullConfidence() {
        let result = ClassificationResult(label: "certain", confidence: 1.0)
        XCTAssertEqual(result.confidence, 1.0, accuracy: 0.001)
    }
}

// MARK: - TryItOutViewModel Tests

@available(iOS 15.0, macOS 12.0, *)
@MainActor
final class TryItOutViewModelTests: XCTestCase {

    private func makeModelInfo(modality: String? = nil) -> PairedModelInfo {
        PairedModelInfo(
            name: "test-model",
            version: "v1.0",
            sizeString: "100 MB",
            runtime: "CoreML",
            tokensPerSecond: 50.0,
            modality: modality
        )
    }

    // MARK: - Modality Routing

    func testDefaultModalityIsText() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo())
        XCTAssertEqual(vm.modality, .text)
    }

    func testTextModality() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))
        XCTAssertEqual(vm.modality, .text)
    }

    func testVisionModality() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "vision"))
        XCTAssertEqual(vm.modality, .vision)
    }

    func testAudioModality() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "audio"))
        XCTAssertEqual(vm.modality, .audio)
    }

    func testClassificationModality() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "classification"))
        XCTAssertEqual(vm.modality, .classification)
    }

    func testLLMAlias() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "llm"))
        XCTAssertEqual(vm.modality, .text)
    }

    func testImageAlias() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "image"))
        XCTAssertEqual(vm.modality, .vision)
    }

    func testSpeechAlias() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "speech"))
        XCTAssertEqual(vm.modality, .audio)
    }

    func testClassifierAlias() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "classifier"))
        XCTAssertEqual(vm.modality, .classification)
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo())
        if case .idle = vm.inferenceState {
            // pass
        } else {
            XCTFail("Expected idle initial state, got \(vm.inferenceState)")
        }
    }

    func testInitialMessagesEmpty() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo())
        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testInitialClassificationResultsEmpty() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo())
        XCTAssertTrue(vm.classificationResults.isEmpty)
    }

    func testInitialLatencyIsNil() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo())
        XCTAssertNil(vm.lastLatencyMs)
    }

    func testModelInfoIsPreserved() {
        let info = makeModelInfo(modality: "vision")
        let vm = TryItOutViewModel(modelInfo: info)
        XCTAssertEqual(vm.modelInfo.name, "test-model")
        XCTAssertEqual(vm.modelInfo.version, "v1.0")
        XCTAssertEqual(vm.modelInfo.runtime, "CoreML")
    }

    // MARK: - Text Inference

    func testSendTextPromptAddsUserMessage() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))
        vm.sendTextPrompt("Hello world")

        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertTrue(vm.messages[0].isUser)
        XCTAssertEqual(vm.messages[0].text, "Hello world")
    }

    func testSendEmptyPromptIgnored() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))
        vm.sendTextPrompt("")

        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testSendWhitespaceOnlyPromptIgnored() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))
        vm.sendTextPrompt("   ")

        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testSendTextPromptSetsLoadingState() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))
        vm.sendTextPrompt("test")

        if case .loading = vm.inferenceState {
            // pass
        } else {
            XCTFail("Expected loading state after sending prompt")
        }
    }

    func testTextInferenceCompletesWithResponse() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))

        let expectation = expectation(description: "Text inference completes")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst() // skip the initial .idle
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.sendTextPrompt("Hello")

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertTrue(vm.messages[0].isUser)
        XCTAssertFalse(vm.messages[1].isUser)
        XCTAssertNotNil(vm.messages[1].latencyMs)
        XCTAssertNotNil(vm.lastLatencyMs)
    }

    // MARK: - Vision Inference

    func testAnalyzeImageSetsLoadingState() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "vision"))
        vm.analyzeImage(imageData: Data([0xFF]), prompt: nil)

        if case .loading = vm.inferenceState {
            // pass
        } else {
            XCTFail("Expected loading state after analyze")
        }
    }

    func testVisionInferenceCompletes() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "vision"))

        let expectation = expectation(description: "Vision inference completes")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst()
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.analyzeImage(imageData: Data([0xFF]), prompt: "describe")

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        if case .result(let output, let latency) = vm.inferenceState {
            XCTAssertFalse(output.isEmpty)
            XCTAssertGreaterThan(latency, 0)
        } else {
            XCTFail("Expected result state, got \(vm.inferenceState)")
        }
    }

    // MARK: - Classification Inference

    func testClassifyImageSetsLoadingState() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "classification"))
        vm.classifyImage(imageData: Data([0xFF]))

        if case .loading = vm.inferenceState {
            // pass
        } else {
            XCTFail("Expected loading state after classify")
        }
    }

    func testClassifyImageClearsOldResults() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "classification"))
        // Should start empty and remain empty during loading
        vm.classifyImage(imageData: Data([0xFF]))
        XCTAssertTrue(vm.classificationResults.isEmpty)
    }

    func testClassificationInferenceCompletes() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "classification"))

        let expectation = expectation(description: "Classification inference completes")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst()
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.classifyImage(imageData: Data([0xFF]))

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        XCTAssertFalse(vm.classificationResults.isEmpty)
        XCTAssertNotNil(vm.lastLatencyMs)

        // Results should be sorted by confidence (highest first)
        if vm.classificationResults.count >= 2 {
            XCTAssertGreaterThanOrEqual(
                vm.classificationResults[0].confidence,
                vm.classificationResults[1].confidence
            )
        }
    }

    // MARK: - Audio Inference

    func testTranscribeAudioSetsLoadingState() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "audio"))
        vm.transcribeAudio(audioData: Data([0x00]))

        if case .loading = vm.inferenceState {
            // pass
        } else {
            XCTFail("Expected loading state after transcribe")
        }
    }

    func testAudioInferenceCompletes() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "audio"))

        let expectation = expectation(description: "Audio inference completes")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst()
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.transcribeAudio(audioData: Data([0x00]))

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        if case .result(let output, let latency) = vm.inferenceState {
            XCTAssertFalse(output.isEmpty)
            XCTAssertGreaterThan(latency, 0)
        } else {
            XCTFail("Expected result state, got \(vm.inferenceState)")
        }
    }

    // MARK: - Reset

    func testResetClearsMessages() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))

        let expectation = expectation(description: "Inference completes before reset")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst()
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.sendTextPrompt("test")

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        XCTAssertFalse(vm.messages.isEmpty)

        vm.reset()

        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testResetClearsClassificationResults() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "classification"))

        let expectation = expectation(description: "Classification completes before reset")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst()
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.classifyImage(imageData: Data([0xFF]))

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        XCTAssertFalse(vm.classificationResults.isEmpty)

        vm.reset()

        XCTAssertTrue(vm.classificationResults.isEmpty)
    }

    func testResetSetsIdleState() {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo())
        vm.sendTextPrompt("test")

        vm.reset()

        if case .idle = vm.inferenceState {
            // pass
        } else {
            XCTFail("Expected idle state after reset")
        }
    }

    func testResetClearsLatency() async {
        let vm = TryItOutViewModel(modelInfo: makeModelInfo(modality: "text"))

        let expectation = expectation(description: "Inference completes before reset")
        var cancellable: AnyCancellable?

        cancellable = vm.$inferenceState
            .dropFirst()
            .sink { state in
                if case .result = state {
                    expectation.fulfill()
                }
            }

        vm.sendTextPrompt("test")

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()

        XCTAssertNotNil(vm.lastLatencyMs)

        vm.reset()

        XCTAssertNil(vm.lastLatencyMs)
    }
}

// MARK: - PairedModelInfo Modality Tests

@available(iOS 15.0, macOS 12.0, *)
final class PairedModelInfoModalityTests: XCTestCase {

    func testModalityFieldPresent() {
        let info = PairedModelInfo(
            name: "test",
            version: "v1",
            sizeString: "50 MB",
            runtime: "CoreML",
            tokensPerSecond: nil,
            modality: "text"
        )
        XCTAssertEqual(info.modality, "text")
    }

    func testModalityFieldNil() {
        let info = PairedModelInfo(
            name: "test",
            version: "v1",
            sizeString: "50 MB",
            runtime: "CoreML",
            tokensPerSecond: nil
        )
        XCTAssertNil(info.modality)
    }

    func testBackwardsCompatibleInit() {
        // Ensure the default parameter works for callers that
        // don't pass modality (backwards compatibility).
        let info = PairedModelInfo(
            name: "test",
            version: "v1",
            sizeString: "50 MB",
            runtime: "CoreML",
            tokensPerSecond: 42.0
        )
        XCTAssertEqual(info.name, "test")
        XCTAssertEqual(info.tokensPerSecond ?? -1, 42.0, accuracy: 0.01)
        XCTAssertNil(info.modality)
    }
}
#endif

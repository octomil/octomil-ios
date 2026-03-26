import Foundation
import XCTest
@testable import Octomil

/// Tests for ``LocalFileModelRuntime`` config threading and modality routing.
final class LocalFileModelRuntimeTests: XCTestCase {

    // MARK: - Config Threading

    func testRunPassesGenerationConfigToEngine() async throws {
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("ok")]

        EngineRegistry.shared.register(modality: .text) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "test-model",
            fileURL: URL(fileURLWithPath: "/tmp/fake.gguf")
        )

        let config = GenerationConfig(
            maxTokens: 256,
            temperature: 0.3,
            topP: 0.8,
            stop: ["END"]
        )
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])],
            generationConfig: config
        )

        _ = try await runtime.run(request: request)

        XCTAssertEqual(mockEngine.recordedConfigs.count, 1)
        let received = mockEngine.recordedConfigs[0]
        XCTAssertEqual(received.maxTokens, 256)
        XCTAssertEqual(received.temperature, 0.3, accuracy: 0.001)
        XCTAssertEqual(received.topP, 0.8, accuracy: 0.001)
        XCTAssertEqual(received.stop, ["END"])
    }

    func testStreamPassesGenerationConfigToEngine() async throws {
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("ok")]

        EngineRegistry.shared.register(modality: .text) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let config = GenerationConfig(
            maxTokens: 256,
            temperature: 0.3,
            topP: 0.8,
            stop: ["END"]
        )
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])],
            generationConfig: config
        )

        let runtime = LocalFileModelRuntime(
            modelId: "test-model",
            fileURL: URL(fileURLWithPath: "/tmp/fake.gguf")
        )

        // Drain the stream
        for try await _ in runtime.stream(request: request) {}

        XCTAssertEqual(mockEngine.recordedConfigs.count, 1)
        let received = mockEngine.recordedConfigs[0]
        XCTAssertEqual(received.maxTokens, 256)
        XCTAssertEqual(received.temperature, 0.3, accuracy: 0.001)
        XCTAssertEqual(received.topP, 0.8, accuracy: 0.001)
        XCTAssertEqual(received.stop, ["END"])
    }

    func testDefaultConfigUsesFrameworkDefaults() async throws {
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("ok")]

        EngineRegistry.shared.register(modality: .text) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "test-model",
            fileURL: URL(fileURLWithPath: "/tmp/fake.gguf")
        )

        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])]
        )

        _ = try await runtime.run(request: request)

        let received = mockEngine.recordedConfigs[0]
        XCTAssertEqual(received.maxTokens, 512)
        XCTAssertEqual(received.temperature, 0.7, accuracy: 0.001)
        XCTAssertEqual(received.topP, 1.0, accuracy: 0.001)
        XCTAssertNil(received.stop)
    }

    // MARK: - Modality Routing

    func testPureAudioResolvesAudioModality() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .audio(data: Data([0x01, 0x02]), mediaType: "audio/wav")
                ])
            ]
        )

        let modality = LocalFileModelRuntime.modality(for: request)
        XCTAssertEqual(modality, .audio)
    }

    func testTextOnlyResolvesTextModality() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [.text("What is 2+2?")])
            ]
        )

        let modality = LocalFileModelRuntime.modality(for: request)
        XCTAssertEqual(modality, .text)
    }

    func testTextPlusImageResolvesTextModality() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .text("Describe this image"),
                    .image(data: Data([0xFF, 0xD8]), mediaType: "image/jpeg")
                ])
            ]
        )

        let modality = LocalFileModelRuntime.modality(for: request)
        XCTAssertEqual(modality, .text)
    }

    func testTextPlusAudioResolvesTextModality() {
        // Text + audio = text modality (user is asking about audio, not pure transcription)
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .text("Summarize this recording"),
                    .audio(data: Data([0x01]), mediaType: "audio/wav")
                ])
            ]
        )

        let modality = LocalFileModelRuntime.modality(for: request)
        XCTAssertEqual(modality, .text)
    }

    func testAudioWithSystemPromptOnlyResolvesAudioModality() {
        // System prompt text should not count as user text
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .system, parts: [.text("You are a transcription engine.")]),
                RuntimeMessage(role: .user, parts: [
                    .audio(data: Data([0x01, 0x02]), mediaType: "audio/wav")
                ])
            ]
        )

        let modality = LocalFileModelRuntime.modality(for: request)
        XCTAssertEqual(modality, .audio)
    }

    func testAudioPlusImageResolvesTextModality() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .audio(data: Data([0x01]), mediaType: "audio/wav"),
                    .image(data: Data([0xFF, 0xD8]), mediaType: "image/jpeg")
                ])
            ]
        )

        let modality = LocalFileModelRuntime.modality(for: request)
        XCTAssertEqual(modality, .text)
    }

    // MARK: - Engine Input

    func testPureAudioInputReturnsRawData() {
        let audioData = Data([0x01, 0x02, 0x03])
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .audio(data: audioData, mediaType: "audio/wav")
                ])
            ]
        )

        let input = LocalFileModelRuntime.engineInput(for: request, modality: .audio)
        XCTAssertTrue(input is Data, "Audio engine should receive Data, got \(type(of: input))")
        XCTAssertEqual(input as? Data, audioData)
    }

    func testTextOnlyInputReturnsString() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [.text("Hello world")])
            ]
        )

        let input = LocalFileModelRuntime.engineInput(for: request, modality: .text)
        XCTAssertTrue(input is String, "Text engine should receive String, got \(type(of: input))")
    }

    func testTextPlusImageInputReturnsMultimodalInput() {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .text("Describe this image"),
                    .image(data: imageData, mediaType: "image/jpeg")
                ])
            ]
        )

        let input = LocalFileModelRuntime.engineInput(for: request, modality: .text)
        guard let mm = input as? MultimodalInput else {
            XCTFail("Expected MultimodalInput, got \(type(of: input))")
            return
        }
        XCTAssertFalse(mm.prompt.isEmpty, "Prompt should contain rendered ChatML")
        XCTAssertEqual(mm.mediaData, imageData)
        XCTAssertEqual(mm.mediaType, "image/jpeg")
    }

    func testTextPlusVideoInputReturnsMultimodalInput() {
        let videoData = Data([0x00, 0x00, 0x00, 0x1C])
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .text("What happens in this video?"),
                    .video(data: videoData, mediaType: "video/mp4")
                ])
            ]
        )

        let input = LocalFileModelRuntime.engineInput(for: request, modality: .text)
        guard let mm = input as? MultimodalInput else {
            XCTFail("Expected MultimodalInput, got \(type(of: input))")
            return
        }
        XCTAssertEqual(mm.mediaData, videoData)
        XCTAssertEqual(mm.mediaType, "video/mp4")
    }

    // MARK: - End-to-end: Config + Routing Together

    func testPureAudioEndToEndPassesConfigAndData() async throws {
        let audioData = Data([0x01, 0x02])
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("transcribed text")]

        EngineRegistry.shared.register(modality: .audio) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "whisper-test",
            fileURL: URL(fileURLWithPath: "/tmp/fake-model")
        )

        let config = GenerationConfig(maxTokens: 1024, temperature: 0.0)
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .audio(data: audioData, mediaType: "audio/wav")
                ])
            ],
            generationConfig: config
        )

        let response = try await runtime.run(request: request)

        XCTAssertEqual(response.text, "transcribed text")
        XCTAssertTrue(mockEngine.recordedInputs[0] is Data)
        XCTAssertEqual(mockEngine.recordedConfigs[0].maxTokens, 1024)
        XCTAssertEqual(mockEngine.recordedConfigs[0].temperature, 0.0, accuracy: 0.001)
    }

    func testTextPlusImageEndToEndPassesMultimodalInput() async throws {
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("A cat sitting on a mat.")]

        EngineRegistry.shared.register(modality: .text) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "vlm-test",
            fileURL: URL(fileURLWithPath: "/tmp/fake-model")
        )

        let imageData = Data([0xFF, 0xD8])
        let config = GenerationConfig(maxTokens: 128, temperature: 0.5, topP: 0.9)
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .text("What is in this image?"),
                    .image(data: imageData, mediaType: "image/jpeg")
                ])
            ],
            generationConfig: config
        )

        let response = try await runtime.run(request: request)

        XCTAssertEqual(response.text, "A cat sitting on a mat.")
        guard let receivedInput = mockEngine.recordedInputs[0] as? MultimodalInput else {
            XCTFail("Expected MultimodalInput")
            return
        }
        XCTAssertEqual(receivedInput.mediaData, imageData)
        XCTAssertEqual(receivedInput.mediaType, "image/jpeg")
        XCTAssertFalse(receivedInput.prompt.isEmpty)

        XCTAssertEqual(mockEngine.recordedConfigs[0].maxTokens, 128)
        XCTAssertEqual(mockEngine.recordedConfigs[0].temperature, 0.5, accuracy: 0.001)
        XCTAssertEqual(mockEngine.recordedConfigs[0].topP, 0.9, accuracy: 0.001)
    }

    // MARK: - Engine Cache Per-Modality

    func testRunResolvesCorrectEnginePerModality() async throws {
        let textEngine = MockStreamingEngine()
        textEngine.chunks = [MockStreamingEngine.ChunkSpec("text reply")]

        let audioEngine = MockStreamingEngine()
        audioEngine.chunks = [MockStreamingEngine.ChunkSpec("transcribed")]

        EngineRegistry.shared.register(modality: .text) { _ in textEngine }
        EngineRegistry.shared.register(modality: .audio) { _ in audioEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "multi-test",
            fileURL: URL(fileURLWithPath: "/tmp/fake-model")
        )

        // First call: text request -> text engine
        let textRequest = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])]
        )
        let textResponse = try await runtime.run(request: textRequest)
        XCTAssertEqual(textResponse.text, "text reply")
        XCTAssertEqual(textEngine.recordedInputs.count, 1)
        XCTAssertEqual(audioEngine.recordedInputs.count, 0)

        // Second call: audio request -> must use audio engine, not cached text engine
        let audioRequest = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [
                .audio(data: Data([0x01]), mediaType: "audio/wav")
            ])]
        )
        let audioResponse = try await runtime.run(request: audioRequest)
        XCTAssertEqual(audioResponse.text, "transcribed")
        XCTAssertEqual(audioEngine.recordedInputs.count, 1,
                       "Audio request must resolve audio engine, not reuse cached text engine")
    }
}

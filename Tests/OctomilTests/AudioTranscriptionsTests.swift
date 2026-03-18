import XCTest
@testable import Octomil

final class AudioTranscriptionsTests: XCTestCase {

    // MARK: - Enum wire values match contract

    func testResponseFormatWireValues() {
        let expected = ["text", "json", "verbose_json", "srt", "vtt"]
        let actual = [
            TranscriptionResponseFormat.text,
            .json, .verboseJson, .srt, .vtt,
        ].map(\.rawValue)
        XCTAssertEqual(expected, actual)
    }

    func testTimestampGranularityWireValues() {
        let expected = ["word", "segment"]
        let actual = [TimestampGranularity.word, .segment].map(\.rawValue)
        XCTAssertEqual(expected, actual)
    }

    // MARK: - TranscriptionResult preserves all contract fields

    func testTranscriptionResultFields() {
        let result = TranscriptionResult(
            text: "hello world",
            segments: [
                TranscriptionSegment(text: "hello", startMs: 0, endMs: 1200, confidence: 0.9),
                TranscriptionSegment(text: "world", startMs: 1200, endMs: 2500),
            ],
            language: "en",
            durationMs: 2500
        )
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.durationMs, 2500)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].confidence, 0.9)
        XCTAssertNil(result.segments[1].confidence)
    }

    // MARK: - TranscriptionSegment has confidence

    func testSegmentConfidenceOptional() {
        let segment = TranscriptionSegment(text: "test", startMs: 0, endMs: 500)
        XCTAssertNil(segment.confidence)
    }

    func testSegmentConfidencePresent() {
        let segment = TranscriptionSegment(text: "test", startMs: 0, endMs: 500, confidence: 0.95)
        XCTAssertEqual(segment.confidence!, 0.95, accuracy: 0.001)
    }

    // MARK: - Validation: accepts supported formats

    func testValidateAcceptsText() throws {
        let transcriptions = makeTranscriptions()
        XCTAssertNoThrow(try transcriptions.validateOptions(
            responseFormat: .text,
            timestampGranularities: []
        ))
    }

    func testValidateAcceptsJson() throws {
        let transcriptions = makeTranscriptions()
        XCTAssertNoThrow(try transcriptions.validateOptions(
            responseFormat: .json,
            timestampGranularities: []
        ))
    }

    // MARK: - Validation: rejects unsupported formats

    func testValidateRejectsVerboseJson() {
        assertUnsupportedFormat(.verboseJson)
    }

    func testValidateRejectsSrt() {
        assertUnsupportedFormat(.srt)
    }

    func testValidateRejectsVtt() {
        assertUnsupportedFormat(.vtt)
    }

    // MARK: - Validation: rejects timestamp granularities

    func testValidateRejectsTimestampGranularities() {
        let transcriptions = makeTranscriptions()
        XCTAssertThrowsError(try transcriptions.validateOptions(
            responseFormat: .text,
            timestampGranularities: [.word]
        )) { error in
            guard case OctomilError.unsupportedModality(let reason) = error else {
                return XCTFail("Expected unsupportedModality, got \(error)")
            }
            XCTAssertTrue(reason.contains("timestamp_granularities"))
        }
    }

    func testValidateAcceptsEmptyTimestampGranularities() throws {
        let transcriptions = makeTranscriptions()
        XCTAssertNoThrow(try transcriptions.validateOptions(
            responseFormat: .text,
            timestampGranularities: []
        ))
    }

    // MARK: - Validation: language is accepted

    func testValidateAcceptsLanguage() throws {
        // language is not validated — it's passed through to the result
        let transcriptions = makeTranscriptions()
        XCTAssertNoThrow(try transcriptions.validateOptions(
            responseFormat: .text,
            timestampGranularities: []
        ))
    }

    // MARK: - create() uses speech runtime, not text-gen

    func testCreatePassesAudioDataViaRuntimeRequest() async throws {
        let mockRuntime = SpyModelRuntime()
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in mockRuntime })

        let audioData = Data([0x01, 0x02, 0x03, 0x04])
        _ = try await transcriptions.create(audio: audioData, model: "whisper-small")

        // Verify the runtime received a request with audio media data
        XCTAssertEqual(mockRuntime.runCallCount, 1, "create() should call runtime.run() exactly once")
        let capturedRequest = mockRuntime.lastRequest
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.mediaData, audioData, "Audio data should be passed to runtime")
        XCTAssertEqual(capturedRequest?.mediaType, "audio", "Media type should be 'audio'")
    }

    func testCreateDoesNotUsePromptForAudioContent() async throws {
        let mockRuntime = SpyModelRuntime()
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in mockRuntime })

        let audioData = Data(repeating: 0xAB, count: 100)
        _ = try await transcriptions.create(audio: audioData, model: "whisper-small")

        // The prompt should be empty — audio content travels via mediaData, not prompt
        let capturedRequest = mockRuntime.lastRequest
        XCTAssertEqual(capturedRequest?.prompt, "", "Audio should not be passed via prompt")
    }

    func testCreateResolvesRuntimeByModelId() async throws {
        var resolvedRef: ModelRef?
        let mockRuntime = SpyModelRuntime()
        let transcriptions = AudioTranscriptions(runtimeResolver: { ref in
            resolvedRef = ref
            return mockRuntime
        })

        _ = try await transcriptions.create(audio: Data([0x00]), model: "whisper-tiny")

        // The resolver should receive the model ID, not a capability
        if case .id(let modelId) = resolvedRef {
            XCTAssertEqual(modelId, "whisper-tiny")
        } else {
            XCTFail("Expected .id(\"whisper-tiny\"), got \(String(describing: resolvedRef))")
        }
    }

    func testCreateThrowsWhenNoRuntimeAvailable() async {
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in nil })

        do {
            _ = try await transcriptions.create(audio: Data([0x00]), model: "missing-model")
            XCTFail("Expected runtimeUnavailable error")
        } catch {
            guard case OctomilError.runtimeUnavailable(let reason) = error else {
                return XCTFail("Expected runtimeUnavailable, got \(error)")
            }
            XCTAssertTrue(reason.contains("missing-model"))
        }
    }

    // MARK: - create() requires model (compile-time enforced)

    /// `model` is a non-optional `String` parameter with no default value.
    /// Omitting it is a compile error. This test documents that contract
    /// requirement by verifying the parameter exists and is used.
    func testCreateRequiresModelParameter() async throws {
        let mockRuntime = SpyModelRuntime()
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in mockRuntime })

        // If model were optional or had a default, this would compile without it.
        // The fact that this test compiles proves model is required.
        _ = try await transcriptions.create(audio: Data([0x00]), model: "whisper-small")
        XCTAssertEqual(mockRuntime.runCallCount, 1)
    }

    // MARK: - create() returns transcription text from runtime

    func testCreateReturnsTranscriptionText() async throws {
        let mockRuntime = SpyModelRuntime(responseText: "Hello world")
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in mockRuntime })

        let result = try await transcriptions.create(
            audio: Data([0x00]),
            model: "whisper-small",
            language: "en"
        )

        XCTAssertEqual(result.text, "Hello world")
        XCTAssertEqual(result.language, "en")
    }

    // MARK: - LocalFileModelRuntime routes audio via mediaData

    func testLocalFileModelRuntimeRoutesAudioModality() async throws {
        // Register a mock audio engine in the EngineRegistry
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("hello from speech engine")]

        EngineRegistry.shared.register(modality: .audio) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "whisper-test",
            fileURL: URL(fileURLWithPath: "/tmp/fake-model")
        )

        let request = RuntimeRequest(
            prompt: "",
            mediaData: Data([0x01, 0x02]),
            mediaType: "audio"
        )

        let response = try await runtime.run(request: request)

        XCTAssertEqual(response.text, "hello from speech engine")
        // Verify the engine received Data input (not the empty prompt string)
        XCTAssertEqual(mockEngine.recordedInputs.count, 1)
        XCTAssertTrue(mockEngine.recordedInputs[0] is Data, "Audio engine should receive Data input")
    }

    func testLocalFileModelRuntimeDefaultsToTextModality() async throws {
        let mockEngine = MockStreamingEngine()
        mockEngine.chunks = [MockStreamingEngine.ChunkSpec("text output")]

        EngineRegistry.shared.register(modality: .text) { _ in mockEngine }
        defer { EngineRegistry.shared.reset() }

        let runtime = LocalFileModelRuntime(
            modelId: "llama-test",
            fileURL: URL(fileURLWithPath: "/tmp/fake-model")
        )

        let request = RuntimeRequest(prompt: "Hello")
        let response = try await runtime.run(request: request)

        XCTAssertEqual(response.text, "text output")
        XCTAssertEqual(mockEngine.recordedInputs.count, 1)
        XCTAssertTrue(mockEngine.recordedInputs[0] is String, "Text engine should receive String input")
    }

    // MARK: - AudioFileDecoder existence

    func testAudioFileDecoderTargetSampleRate() {
        XCTAssertEqual(AudioFileDecoder.targetSampleRate, 16_000)
    }

    func testAudioFileDecoderCanBeInstantiated() {
        let decoder = AudioFileDecoder()
        // The decoder should be a value type that can be instantiated
        XCTAssertEqual(AudioFileDecoder.targetSampleRate, 16_000)
        _ = decoder // suppress unused warning
    }

    // MARK: - Helpers

    private func makeTranscriptions() -> AudioTranscriptions {
        AudioTranscriptions(runtimeResolver: { _ in nil })
    }

    private func assertUnsupportedFormat(
        _ format: TranscriptionResponseFormat,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let transcriptions = makeTranscriptions()
        XCTAssertThrowsError(
            try transcriptions.validateOptions(
                responseFormat: format,
                timestampGranularities: []
            ),
            file: file,
            line: line
        ) { error in
            guard case OctomilError.unsupportedModality(let reason) = error else {
                return XCTFail("Expected unsupportedModality, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                reason.contains(format.rawValue),
                "Message should contain '\(format.rawValue)': \(reason)",
                file: file,
                line: line
            )
        }
    }
}

// MARK: - SpyModelRuntime

/// A mock ``ModelRuntime`` that captures requests for verification.
private final class SpyModelRuntime: ModelRuntime, @unchecked Sendable {

    let capabilities = RuntimeCapabilities(supportsStreaming: false)

    private(set) var runCallCount = 0
    private(set) var lastRequest: RuntimeRequest?
    private let responseText: String

    init(responseText: String = "") {
        self.responseText = responseText
    }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        runCallCount += 1
        lastRequest = request
        return RuntimeResponse(text: responseText)
    }

    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func close() {}
}

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

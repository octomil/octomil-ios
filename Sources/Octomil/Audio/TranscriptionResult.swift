import Foundation

// MARK: - TranscriptionSegment

/// A time-aligned segment of a transcription.
public struct TranscriptionSegment: Sendable {
    /// The transcribed text for this segment.
    public let text: String
    /// Start time in milliseconds from the beginning of the audio.
    public let startMs: Int
    /// End time in milliseconds from the beginning of the audio.
    public let endMs: Int
    /// Confidence score (0.0 to 1.0), if available.
    public let confidence: Double?

    public init(text: String, startMs: Int, endMs: Int, confidence: Double? = nil) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.confidence = confidence
    }
}

// MARK: - TranscriptionResult

/// The result of a completed transcription.
public struct TranscriptionResult: Sendable {
    /// The full transcribed text.
    public let text: String
    /// Time-aligned segments.
    public let segments: [TranscriptionSegment]
    /// Detected or requested language code (e.g. "en").
    public let language: String?
    /// Total audio duration in milliseconds.
    public let durationMs: Int?

    public init(
        text: String,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationMs: Int? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationMs = durationMs
    }
}

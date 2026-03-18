import Foundation

/// Format of the transcription output, matching contract v1.5.0.
public enum TranscriptionResponseFormat: String, Sendable {
    case text
    case json
    case verboseJson = "verbose_json"
    case srt
    case vtt
}

/// Granularity level for timestamp generation, matching contract v1.5.0.
public enum TimestampGranularity: String, Sendable {
    case word
    case segment
}

/// Audio transcription API — `client.audio.transcriptions.create()`.
///
/// Routes through the model runtime for speech-to-text inference.
///
/// ```swift
/// let result = try await client.audio.transcriptions.create(
///     audio: audioData,
///     model: "whisper-small"
/// )
/// print(result.text)
/// ```
public final class AudioTranscriptions: @unchecked Sendable {

    private let runtimeResolver: (ModelRef) -> ModelRuntime?

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.runtimeResolver = runtimeResolver
    }

    // MARK: - Create

    /// Transcribe audio to text.
    ///
    /// - Parameters:
    ///   - audio: Raw audio data (WAV, MP3, etc.).
    ///   - model: Model name (required per contract).
    ///   - language: Optional language hint (BCP-47 code, e.g. "en").
    ///   - responseFormat: Format of the transcription output (default: `.text`).
    ///     Only `.text` and `.json` are currently supported by local engines.
    ///   - timestampGranularities: Granularities of timestamps to include.
    ///     Not currently supported — will throw `.unsupportedModality`.
    /// - Returns: The transcription result.
    /// - Throws: `OctomilError.unsupportedModality` for formats or granularities
    ///   that the current runtime cannot honor.
    public func create(
        audio: Data,
        model: String,
        language: String? = nil,
        responseFormat: TranscriptionResponseFormat = .text,
        timestampGranularities: [TimestampGranularity] = []
    ) async throws -> TranscriptionResult {
        try validateOptions(
            responseFormat: responseFormat,
            timestampGranularities: timestampGranularities
        )

        guard let runtime = runtimeResolver(.id(model)) else {
            throw OctomilError.runtimeUnavailable(reason: "No runtime for model '\(model)'")
        }

        let request = RuntimeRequest(
            prompt: "",
            mediaData: audio,
            mediaType: "audio"
        )

        let response = try await runtime.run(request: request)

        return TranscriptionResult(
            text: response.text,
            language: language
        )
    }

    // MARK: - Validation

    /// Reject options the current engine cannot honor.
    ///
    /// Uses `unsupportedModality` (not `invalidInput`) because these are
    /// contract-valid values that the local engine doesn't support.
    func validateOptions(
        responseFormat: TranscriptionResponseFormat,
        timestampGranularities: [TimestampGranularity]
    ) throws {
        switch responseFormat {
        case .text, .json:
            break // supported
        case .verboseJson, .srt, .vtt:
            throw OctomilError.unsupportedModality(
                reason: "response_format '\(responseFormat.rawValue)' is not supported "
                    + "by the current runtime. Supported: text, json."
            )
        }

        if !timestampGranularities.isEmpty {
            throw OctomilError.unsupportedModality(
                reason: "timestamp_granularities is not supported by the current runtime."
            )
        }
    }
}

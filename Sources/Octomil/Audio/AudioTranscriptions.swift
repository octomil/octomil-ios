import Foundation

/// Audio transcription API.
///
/// Wraps the underlying audio runtime to provide speech-to-text.
///
/// ```swift
/// let result = try await client.audio.transcriptions.create(
///     model: .capability(.transcription),
///     audio: audioData
/// )
/// print(result.text)
/// ```
public final class AudioTranscriptions: @unchecked Sendable {

    private let runtimeResolver: (ModelRef) -> ModelRuntime?

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.runtimeResolver = runtimeResolver
    }

    // MARK: - Non-streaming

    /// Transcribe audio to text.
    ///
    /// - Parameters:
    ///   - model: Model reference — by ID or capability.
    ///   - audio: Raw audio data (WAV, MP3, etc.).
    ///   - language: Optional language hint (BCP 47 code, e.g. "en").
    /// - Returns: The transcription result.
    public func create(
        model: ModelRef = .capability(.transcription),
        audio: Data,
        language: String? = nil
    ) async throws -> TranscriptionResult {
        guard let runtime = runtimeResolver(model) else {
            throw OctomilError.runtimeUnavailable(reason: "No runtime for transcription model")
        }

        let request = RuntimeRequest(
            prompt: language ?? "",
            mediaData: audio,
            mediaType: "audio"
        )

        let response = try await runtime.run(request: request)

        return TranscriptionResult(
            text: response.text,
            language: language
        )
    }

    // MARK: - Streaming

    /// Stream transcription segments as they are produced.
    ///
    /// - Parameters:
    ///   - model: Model reference — by ID or capability.
    ///   - audio: Raw audio data.
    /// - Returns: An async stream of transcription segments.
    public func stream(
        model: ModelRef = .capability(.transcription),
        audio: Data
    ) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        guard let runtime = runtimeResolver(model) else {
            return AsyncThrowingStream {
                throw OctomilError.runtimeUnavailable(reason: "No runtime for transcription model")
            }
        }

        let request = RuntimeRequest(
            prompt: "",
            mediaData: audio,
            mediaType: "audio"
        )

        let runtimeStream = runtime.stream(request: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var offsetMs = 0
                    for try await chunk in runtimeStream {
                        if let text = chunk.text, !text.isEmpty {
                            let segment = TranscriptionSegment(
                                text: text,
                                startMs: offsetMs,
                                endMs: offsetMs + 500 // estimate — real engine provides timing
                            )
                            continuation.yield(segment)
                            offsetMs += 500
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

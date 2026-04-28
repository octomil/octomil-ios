import Foundation

/// Namespace for audio APIs on ``OctomilClient``.
///
/// ```swift
/// let result = try await client.audio.transcriptions.create(audio: audioData, model: "whisper-small")
/// print(result.text)
/// let speech = try await client.audio.speech.create(model: "kokoro-82m", input: "Hello")
/// ```
public final class OctomilAudio: @unchecked Sendable {

    /// Audio transcription API.
    public let transcriptions: AudioTranscriptions
    /// Text-to-speech API.
    public let speech: AudioSpeech

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.transcriptions = AudioTranscriptions(runtimeResolver: runtimeResolver)
        self.speech = AudioSpeech()
    }

    /// Test seam: build with explicit speech facade (e.g. with a
    /// candidate override or test recipe registry).
    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?, speech: AudioSpeech) {
        self.transcriptions = AudioTranscriptions(runtimeResolver: runtimeResolver)
        self.speech = speech
    }
}

import Foundation

/// Namespace for audio APIs on ``OctomilClient``.
///
/// ```swift
/// let result = try await client.audio.transcriptions.create(audio: audioData)
/// print(result.text)
/// ```
public final class OctomilAudio: @unchecked Sendable {

    /// Audio transcription API.
    public let transcriptions: AudioTranscriptions

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.transcriptions = AudioTranscriptions(runtimeResolver: runtimeResolver)
    }
}

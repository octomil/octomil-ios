import Foundation

/// Namespace for audio APIs on ``OctomilClient``.
///
/// ```swift
/// let result = try await client.audio.transcriptions.create(audio: audioData, model: "whisper-small")
/// print(result.text)
/// let speech = try await client.audio.speech.create(model: "kokoro-82m", input: "Hello")
/// let transitions = try await client.audio.vad.detect(audio: pcmData, sampleRate: 16000)
/// let vector = try await client.audio.speakerEmbedding.create(audio: pcmData, sampleRate: 16000)
/// let segments = try await client.audio.diarization.create(audio: pcmData, sampleRate: 16000)
/// for try await chunk in client.audio.speech.ttsStream.stream(model: "kokoro-82m", input: "Hello") { … }
/// ```
public final class OctomilAudio: @unchecked Sendable {

    /// Audio transcription API.
    public let transcriptions: AudioTranscriptions
    /// Text-to-speech batch API.
    public let speech: AudioSpeech
    /// Voice-activity detection API (``audio.vad``).
    public let vad: FacadeVad
    /// Speaker embedding API (``audio.speaker.embedding``).
    public let speakerEmbedding: FacadeSpeakerEmbedding
    /// Speaker diarization API (``audio.diarization``).
    public let diarization: FacadeDiarization
    /// Streaming TTS API (``audio.tts.stream``).
    public let ttsStream: FacadeTtsStream

    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?) {
        self.transcriptions = AudioTranscriptions(runtimeResolver: runtimeResolver)
        self.speech = AudioSpeech()
        // The VAD / speaker-embedding / diarization / tts-stream facades
        // use FFINativeRuntime (or a test stub) via the nativeRuntimeProvider
        // closure. Production callers get the runtime unavailable error until
        // FFINativeRuntime.openSession is wired; tests inject a StubRuntime.
        let unavailableProvider: @Sendable () async throws -> any NativeRuntime = {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "Native runtime not configured. Set OCTOMIL_RUNTIME_LIBRARY or link the runtime framework."
            )
        }
        self.vad = FacadeVad(nativeRuntimeProvider: unavailableProvider)
        self.speakerEmbedding = FacadeSpeakerEmbedding(nativeRuntimeProvider: unavailableProvider)
        self.diarization = FacadeDiarization(nativeRuntimeProvider: unavailableProvider)
        self.ttsStream = FacadeTtsStream(nativeRuntimeProvider: unavailableProvider)
    }

    /// Full init — allows injection of all facades.
    init(
        runtimeResolver: @escaping (ModelRef) -> ModelRuntime?,
        speech: AudioSpeech,
        vad: FacadeVad,
        speakerEmbedding: FacadeSpeakerEmbedding,
        diarization: FacadeDiarization,
        ttsStream: FacadeTtsStream
    ) {
        self.transcriptions = AudioTranscriptions(runtimeResolver: runtimeResolver)
        self.speech = speech
        self.vad = vad
        self.speakerEmbedding = speakerEmbedding
        self.diarization = diarization
        self.ttsStream = ttsStream
    }

    /// Test seam: build with explicit speech facade (e.g. with a
    /// candidate override or test recipe registry).
    init(runtimeResolver: @escaping (ModelRef) -> ModelRuntime?, speech: AudioSpeech) {
        self.transcriptions = AudioTranscriptions(runtimeResolver: runtimeResolver)
        self.speech = speech
        let unavailableProvider: @Sendable () async throws -> any NativeRuntime = {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "Native runtime not configured."
            )
        }
        self.vad = FacadeVad(nativeRuntimeProvider: unavailableProvider)
        self.speakerEmbedding = FacadeSpeakerEmbedding(nativeRuntimeProvider: unavailableProvider)
        self.diarization = FacadeDiarization(nativeRuntimeProvider: unavailableProvider)
        self.ttsStream = FacadeTtsStream(nativeRuntimeProvider: unavailableProvider)
    }
}

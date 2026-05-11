// Auto-generated from octomil-contracts runtime_capability.json. Do not edit.
//
// Source of truth for capability strings used in BOTH directions of the runtime ABI:
//   (a) advertised via oct_runtime_capabilities().supported_capabilities[]
//   (b) requested via oct_session_config_t.capability

public enum RuntimeCapability: String, Codable, Sendable {
    case audioDiarization = "audio.diarization"
    case audioRealtimeSession = "audio.realtime.session"
    case audioSpeakerEmbedding = "audio.speaker.embedding"
    case audioSttBatch = "audio.stt.batch"
    case audioSttStream = "audio.stt.stream"
    case audioTranscription = "audio.transcription"
    case audioTtsBatch = "audio.tts.batch"
    case audioTtsStream = "audio.tts.stream"
    case audioVad = "audio.vad"
    case cacheIntrospect = "cache.introspect"
    case chatCompletion = "chat.completion"
    case chatStream = "chat.stream"
    case embeddingsImage = "embeddings.image"
    case embeddingsText = "embeddings.text"
    case indexVectorQuery = "index.vector.query"
}

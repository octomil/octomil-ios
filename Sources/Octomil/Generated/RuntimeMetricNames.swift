// Auto-generated from octomil-contracts runtime_metric.json. Do not edit.
//
// Closed set of metric names emitted by the native runtime via OCT_EVENT_METRIC.

public enum RuntimeMetricName {
    public static let audioFeatureReuseTotal = "audio.feature_reuse_total"
    public static let cacheAudioPhonemeHitRate = "cache.audio.phoneme.hit_rate"
    public static let cacheAudioPhraseHitRate = "cache.audio.phrase.hit_rate"
    public static let cacheAudioVoiceHitRate = "cache.audio.voice.hit_rate"
    public static let cacheBytes = "cache.bytes"
    public static let cacheDisabledTotal = "cache.disabled_total"
    public static let cacheEvictionTotal = "cache.eviction_total"
    public static let cacheHitTotal = "cache.hit_total"
    public static let cacheLookupMs = "cache.lookup_ms"
    public static let cacheMissTotal = "cache.miss_total"
    public static let cacheRouteHitRate = "cache.route.hit_rate"
    public static let embeddingsCacheHitTotal = "embeddings.cache_hit_total"
    public static let gpuActivePct = "gpu.active_pct"
    public static let gpuPowerW = "gpu.power_w"
    public static let kvPrefixBytes = "kv_prefix.bytes"
    public static let kvPrefixCacheHit = "kv_prefix.cache_hit"
    public static let kvPrefixCacheHitRate = "kv_prefix.cache_hit_rate"
    public static let kvPrefixCacheMiss = "kv_prefix.cache_miss"
    public static let kvPrefixSavedTokens = "kv_prefix.saved_tokens"
    public static let kvPrefixSavedTokensTotal = "kv_prefix.saved_tokens_total"
    public static let mimiFramesDroppedTotal = "mimi.frames_dropped_total"
    public static let mimiFramesEncodedTotal = "mimi.frames_encoded_total"
    public static let modelEvictCountTotal = "model.evict_count_total"
    public static let modelLoadMs = "model.load_ms"
    public static let modelWarmMs = "model.warm_ms"
    public static let schedulerPreemptCountTotal = "scheduler.preempt_count_total"
    public static let schedulerQueueDepth = "scheduler.queue_depth"
    public static let speakerAudioDurationMs = "speaker.audio_duration_ms"
    public static let speakerCacheHitTotal = "speaker.cache_hit_total"
    public static let speakerInferenceMs = "speaker.inference_ms"
    public static let speakerSetupMs = "speaker.setup_ms"
    public static let sttVadGatedMsSaved = "stt.vad_gated_ms_saved"
    public static let ttsAudioCacheHitTotal = "tts.audio_cache_hit_total"
    public static let ttsAudioCacheMissTotal = "tts.audio_cache_miss_total"
    public static let ttsAudioDurationMs = "tts.audio_duration_ms"
    public static let ttsChunkCount = "tts.chunk_count"
    public static let ttsFirstAudioMs = "tts.first_audio_ms"
    public static let ttsFirstChunkAfterSynthMs = "tts.first_chunk_after_synth_ms"
    public static let ttsFrontendCacheClearTotal = "tts.frontend_cache_clear_total"
    public static let ttsFrontendCacheHitTotal = "tts.frontend_cache_hit_total"
    public static let ttsFrontendCacheRejectEmptyTotal = "tts.frontend_cache_reject_empty_total"
    public static let ttsFrontendCacheRejectOversizeTotal = "tts.frontend_cache_reject_oversize_total"
    public static let ttsRealTimeFactor = "tts.real_time_factor"
    public static let ttsSessionOpenMs = "tts.session_open_ms"
    public static let ttsSynthesizeMs = "tts.synthesize_ms"
    public static let vadAudioDurationMs = "vad.audio_duration_ms"
    public static let vadInferenceMs = "vad.inference_ms"
    public static let vadRealTimeFactor = "vad.real_time_factor"
    public static let vadSetupMs = "vad.setup_ms"
    public static let whisperAudioDurationMs = "whisper.audio_duration_ms"
    public static let whisperDecodeMs = "whisper.decode_ms"
    public static let whisperDigestAdmissionOk = "whisper.digest_admission_ok"
    public static let whisperLoadMs = "whisper.load_ms"
    public static let whisperQueueMs = "whisper.queue_ms"
    public static let whisperRealTimeFactor = "whisper.real_time_factor"
    public static let whisperSessionOpenMs = "whisper.session_open_ms"

    public static let allRuntimeMetrics = [
        audioFeatureReuseTotal,
        cacheAudioPhonemeHitRate,
        cacheAudioPhraseHitRate,
        cacheAudioVoiceHitRate,
        cacheBytes,
        cacheDisabledTotal,
        cacheEvictionTotal,
        cacheHitTotal,
        cacheLookupMs,
        cacheMissTotal,
        cacheRouteHitRate,
        embeddingsCacheHitTotal,
        gpuActivePct,
        gpuPowerW,
        kvPrefixBytes,
        kvPrefixCacheHit,
        kvPrefixCacheHitRate,
        kvPrefixCacheMiss,
        kvPrefixSavedTokens,
        kvPrefixSavedTokensTotal,
        mimiFramesDroppedTotal,
        mimiFramesEncodedTotal,
        modelEvictCountTotal,
        modelLoadMs,
        modelWarmMs,
        schedulerPreemptCountTotal,
        schedulerQueueDepth,
        speakerAudioDurationMs,
        speakerCacheHitTotal,
        speakerInferenceMs,
        speakerSetupMs,
        sttVadGatedMsSaved,
        ttsAudioCacheHitTotal,
        ttsAudioCacheMissTotal,
        ttsAudioDurationMs,
        ttsChunkCount,
        ttsFirstAudioMs,
        ttsFirstChunkAfterSynthMs,
        ttsFrontendCacheClearTotal,
        ttsFrontendCacheHitTotal,
        ttsFrontendCacheRejectEmptyTotal,
        ttsFrontendCacheRejectOversizeTotal,
        ttsRealTimeFactor,
        ttsSessionOpenMs,
        ttsSynthesizeMs,
        vadAudioDurationMs,
        vadInferenceMs,
        vadRealTimeFactor,
        vadSetupMs,
        whisperAudioDurationMs,
        whisperDecodeMs,
        whisperDigestAdmissionOk,
        whisperLoadMs,
        whisperQueueMs,
        whisperRealTimeFactor,
        whisperSessionOpenMs,
    ]
}

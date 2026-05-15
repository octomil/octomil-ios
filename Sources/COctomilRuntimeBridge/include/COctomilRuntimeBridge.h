#ifndef COCTOMIL_RUNTIME_BRIDGE_H
#define COCTOMIL_RUNTIME_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t oct_status_t;
typedef uint32_t oct_priority_t;
typedef uint32_t oct_event_type_t;
typedef uint32_t oct_error_code_t;
typedef uint32_t oct_cache_scope_t;

#define OCT_EVENT_NONE                  ((oct_event_type_t)0)
#define OCT_EVENT_SESSION_STARTED       ((oct_event_type_t)1)
#define OCT_EVENT_AUDIO_CHUNK           ((oct_event_type_t)2)
#define OCT_EVENT_TRANSCRIPT_CHUNK      ((oct_event_type_t)3)
#define OCT_EVENT_TURN_ENDED            ((oct_event_type_t)5)
#define OCT_EVENT_ERROR                 ((oct_event_type_t)7)
#define OCT_EVENT_SESSION_COMPLETED     ((oct_event_type_t)8)
#define OCT_EVENT_MODEL_LOADED          ((oct_event_type_t)10)
#define OCT_EVENT_MODEL_EVICTED         ((oct_event_type_t)11)
#define OCT_EVENT_CACHE_HIT             ((oct_event_type_t)12)
#define OCT_EVENT_CACHE_MISS            ((oct_event_type_t)13)
#define OCT_EVENT_METRIC                ((oct_event_type_t)19)
#define OCT_EVENT_EMBEDDING_VECTOR      ((oct_event_type_t)20)
#define OCT_EVENT_TRANSCRIPT_SEGMENT    ((oct_event_type_t)21)
#define OCT_EVENT_TRANSCRIPT_FINAL      ((oct_event_type_t)22)
#define OCT_EVENT_TTS_AUDIO_CHUNK       ((oct_event_type_t)23)
#define OCT_EVENT_VAD_TRANSITION        ((oct_event_type_t)24)
#define OCT_EVENT_DIARIZATION_SEGMENT   ((oct_event_type_t)25)

#define OCT_PRIORITY_SPECULATIVE  ((oct_priority_t)0)
#define OCT_PRIORITY_PREFETCH     ((oct_priority_t)1)
#define OCT_PRIORITY_FOREGROUND   ((oct_priority_t)2)

#define OCT_STATUS_OK                ((oct_status_t)0)
#define OCT_STATUS_INVALID_INPUT     ((oct_status_t)1)
#define OCT_STATUS_UNSUPPORTED       ((oct_status_t)2)
#define OCT_STATUS_NOT_FOUND         ((oct_status_t)3)
#define OCT_STATUS_BUSY              ((oct_status_t)4)
#define OCT_STATUS_TIMEOUT           ((oct_status_t)5)
#define OCT_STATUS_CANCELLED         ((oct_status_t)6)
#define OCT_STATUS_INTERNAL          ((oct_status_t)7)
#define OCT_STATUS_VERSION_MISMATCH  ((oct_status_t)8)

#define OCT_RUNTIME_CONFIG_VERSION   1
#define OCT_CAPABILITIES_VERSION     1
#define OCT_MODEL_CONFIG_VERSION      1
#define OCT_SESSION_CONFIG_VERSION    3
#define OCT_EVENT_VERSION             2
#define OCT_SAMPLE_FORMAT_PCM_S16LE   ((uint32_t)1)
#define OCT_SAMPLE_FORMAT_PCM_F32LE   ((uint32_t)2)

/* v0.1.12 — image input ABI surface (ABI minor 11).
 *
 * Per octomil-runtime PR #86 (1d92e35): the embeddings.image lane adds
 * a dedicated input view + send function. The runtime export is a STUB
 * that returns OCT_STATUS_UNSUPPORTED on every non-NULL input until the
 * adapter PR lands. The capability "embeddings.image" remains
 * BLOCKED_WITH_PROOF and is not advertised by oct_runtime_capabilities.
 *
 * Symbols (oct_image_view_t, oct_session_send_image, oct_image_view_size,
 * OCT_IMAGE_MIME_*, OCT_EMBED_POOLING_IMAGE_CLIP) are forward-declared
 * here so the Swift binding can cdef against them and dlsym at load
 * time. Symbol PRESENCE is gated by the runtime ABI minor (>= 11);
 * symbol BEHAVIOUR (whether the capability is live) is gated by the
 * runtime capability probe at session-open time. This binding's
 * required ABI floor (NativeABI.requiredMinor) stays at 10 — the image
 * path enforces the >= 11 check inline.
 */
#define OCT_IMAGE_MIME_UNKNOWN  ((uint32_t)0)  /* future-compat sentinel; never set by callers */
#define OCT_IMAGE_MIME_PNG      ((uint32_t)1)  /* image/png — encoded */
#define OCT_IMAGE_MIME_JPEG     ((uint32_t)2)  /* image/jpeg — encoded */
#define OCT_IMAGE_MIME_WEBP     ((uint32_t)3)  /* image/webp — encoded */
#define OCT_IMAGE_MIME_RGB8     ((uint32_t)4)  /* raw decoded uint8 RGB pixel buffer */

#define OCT_EMBED_POOLING_IMAGE_CLIP ((uint32_t)5) /* CLIP/SigLIP-style image embedding */

typedef void (*oct_telemetry_sink_fn)(
    const void* event,
    void* user_data
);

typedef struct oct_runtime oct_runtime_t;
typedef struct oct_model oct_model_t;
typedef struct oct_session oct_session_t;

typedef struct {
    uint32_t version;
    const char* model_uri;
    const char* artifact_digest;
    const char* engine_hint;
    const char* policy_preset;
    uint32_t accelerator_pref;
    uint64_t ram_budget_bytes;
    void* user_data;
} oct_model_config_t;

typedef struct {
    uint32_t version;
    const char* model_uri;
    const char* capability;
    const char* locality;
    const char* policy_preset;
    const char* speaker_id;
    uint32_t sample_rate_in;
    uint32_t sample_rate_out;
    oct_priority_t priority;
    void* user_data;
    const char* request_id;
    const char* route_id;
    const char* trace_id;
    const char* kv_prefix_key;
    oct_model_t* model;
} oct_session_config_t;

typedef struct {
    const float* samples;
    uint32_t n_frames;
    uint32_t sample_rate;
    uint16_t channels;
    uint16_t _reserved0;
} oct_audio_view_t;

/* v0.1.12 — image-input view, caller-owned for the duration of the
 * oct_session_send_image call. Layout MUST match the runtime header
 * exactly (PR #86 1d92e35); the size/offsets are pinned by
 * NativeRuntimeTypeTests + the runtime-side
 * test_oct_session_send_image_shape.cpp regression. */
typedef struct {
    const uint8_t* bytes;        /* borrowed; lifetime = call duration only */
    size_t         n_bytes;      /* encoded byte length; 0 => INVALID_INPUT */
    uint32_t       mime;         /* OCT_IMAGE_MIME_* closed enum */
    uint32_t       _reserved0;   /* padding; always 0 */
} oct_image_view_t;

typedef struct {
    uint32_t version;
    size_t size;
    oct_event_type_t type;
    uint64_t monotonic_ns;
    void* user_data;
    union {
        struct {
            const uint8_t* pcm;
            uint32_t n_bytes;
            uint32_t sample_rate;
            uint32_t sample_format;
            uint16_t channels;
            uint8_t is_final;
            uint8_t _reserved0;
        } audio_chunk;
        struct {
            const char* utf8;
            uint32_t n_bytes;
        } transcript_chunk;
        struct {
            const char* code;
            const char* message;
            oct_error_code_t error_code;
            uint32_t _reserved0;
        } error;
        struct {
            const char* engine;
            const char* model_digest;
            const char* locality;
            const char* streaming_mode;
            const char* runtime_build_tag;
        } session_started;
        struct {
            float setup_ms;
            float engine_first_chunk_ms;
            float e2e_first_chunk_ms;
            float total_latency_ms;
            float queued_ms;
            uint32_t observed_chunks;
            uint8_t capability_verified;
            uint8_t _reserved0;
            uint16_t _reserved1;
            oct_status_t terminal_status;
        } session_completed;
        struct {
            uint32_t n_frames_dropped;
            uint32_t sample_rate;
            uint16_t channels;
            uint16_t _reserved0;
            const char* reason;
            uint64_t dropped_at_ns;
        } input_dropped;
        struct {
            const char* engine;
            const char* model_id;
            const char* artifact_digest;
            uint64_t load_ms;
            uint64_t warm_ms;
            const char* policy_preset;
            void* config_user_data;
            const char* source;
        } model_loaded;
        struct {
            const char* engine;
            const char* model_id;
            const char* artifact_digest;
            uint64_t freed_bytes;
            const char* reason;
            void* config_user_data;
        } model_evicted;
        struct {
            const char* layer;
            uint32_t saved_tokens;
            uint32_t _reserved0;
        } cache;
        struct {
            uint32_t queue_position;
            uint32_t queue_depth;
        } queued;
        struct {
            uint32_t preempted_by_priority;
            uint32_t _reserved0;
            const char* reason;
        } preempted;
        struct {
            uint64_t ram_available_bytes;
            uint8_t severity;
            uint8_t _reserved0;
            uint16_t _reserved1;
            uint32_t _reserved2;
        } memory_pressure;
        struct {
            uint8_t state;
            uint8_t _reserved0;
            uint16_t _reserved1;
            uint32_t _reserved2;
        } thermal_state;
        struct {
            uint32_t timeout_ms;
            uint32_t _reserved0;
            const char* phase;
        } watchdog_timeout;
        struct {
            const char* name;
            double value;
        } metric;
        struct {
            const float* values;
            uint32_t n_dim;
            uint32_t n_input_tokens;
            uint32_t index;
            uint32_t pooling_type;
            uint8_t is_normalized;
            uint8_t _reserved0;
            uint16_t _reserved1;
        } embedding_vector;
        struct {
            uint32_t transition_kind;
            uint32_t timestamp_ms;
            float confidence;
            uint32_t _reserved0;
        } vad_transition;
        struct {
            const char* utf8;
            uint32_t n_bytes;
            uint32_t start_ms;
            uint32_t end_ms;
            uint32_t segment_index;
            uint8_t is_final;
            uint8_t _reserved0;
            uint16_t _reserved1;
        } transcript_segment;
        struct {
            const char* utf8;
            uint32_t n_bytes;
            uint32_t n_segments;
            uint32_t duration_ms;
            uint32_t _reserved0;
            uint32_t _reserved1;
        } transcript_final;
        struct {
            uint32_t start_ms;
            uint32_t end_ms;
            uint16_t speaker_id;
            uint16_t _reserved0;
            uint32_t _reserved1;
            const char* speaker_label;
        } diarization_segment;
        struct {
            const uint8_t* pcm;
            uint32_t n_bytes;
            uint32_t sample_rate;
            uint32_t sample_format;
            uint16_t channels;
            uint8_t is_final;
            uint8_t _reserved0;
        } tts_audio_chunk;
    } data;
    const char* request_id;
    const char* route_id;
    const char* trace_id;
    const char* engine_version;
    const char* adapter_version;
    const char* accelerator;
    const char* artifact_digest;
    uint8_t cache_was_hit;
    uint8_t _reserved0;
    uint16_t _reserved1;
    uint32_t _reserved2;
} oct_event_t;

typedef struct {
    uint32_t version;
    const char* artifact_root;
    oct_telemetry_sink_fn telemetry_sink;
    void* telemetry_user_data;
    uint32_t max_sessions;
} oct_runtime_config_t;

typedef struct {
    uint32_t version;
    size_t size;
    const char** supported_engines;
    const char** supported_capabilities;
    const char** supported_archs;
    uint64_t ram_total_bytes;
    uint64_t ram_available_bytes;
    uint8_t has_apple_silicon;
    uint8_t has_cuda;
    uint8_t has_metal;
    uint8_t _reserved0;
} oct_capabilities_t;

oct_status_t oct_model_open(
    oct_runtime_t* runtime,
    const oct_model_config_t* config,
    oct_model_t** out_model
);
oct_status_t oct_model_warm(oct_model_t* model);
oct_status_t oct_model_evict(oct_model_t* model);
oct_status_t oct_model_close(oct_model_t* model);
size_t oct_model_config_size(void);

oct_status_t oct_session_open(
    oct_runtime_t* runtime,
    const oct_session_config_t* config,
    oct_session_t** out
);
void oct_session_close(oct_session_t* session);
oct_status_t oct_session_send_audio(oct_session_t* session, const oct_audio_view_t* audio);
oct_status_t oct_session_send_text(oct_session_t* session, const char* utf8);
/* v0.1.12 — image-input stub. Returns OCT_STATUS_UNSUPPORTED until the
 * embeddings.image adapter lands; NULL session/view returns
 * OCT_STATUS_INVALID_INPUT. Symbol presence requires ABI minor >= 11. */
oct_status_t oct_session_send_image(oct_session_t* session, const oct_image_view_t* view);
oct_status_t oct_session_poll_event(oct_session_t* session, oct_event_t* out, uint32_t timeout_ms);
oct_status_t oct_session_cancel(oct_session_t* session);
size_t oct_session_config_size(void);
size_t oct_audio_view_size(void);
/* v0.1.12 — sizeof(oct_image_view_t) introspection. Symbol presence
 * requires ABI minor >= 11. Mirrors oct_audio_view_size. */
size_t oct_image_view_size(void);
size_t oct_event_size(void);

oct_status_t oct_runtime_cache_clear_all(oct_runtime_t* runtime);
oct_status_t oct_runtime_cache_clear_capability(oct_runtime_t* runtime, const char* capability_id);
oct_status_t oct_runtime_cache_clear_scope(oct_runtime_t* runtime, oct_cache_scope_t scope_id);
oct_status_t oct_runtime_cache_introspect(oct_runtime_t* runtime, char* out_json_buf, size_t buf_len);

#ifdef __cplusplus
}
#endif

#endif

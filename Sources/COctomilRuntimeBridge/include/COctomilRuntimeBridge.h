#ifndef COCTOMIL_RUNTIME_BRIDGE_H
#define COCTOMIL_RUNTIME_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t oct_status_t;

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

typedef void (*oct_telemetry_sink_fn)(
    const void* event,
    void* user_data
);

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

#ifdef __cplusplus
}
#endif

#endif

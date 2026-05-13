import Foundation
import XCTest
@testable import Octomil

#if os(macOS)
final class FFINativeRuntimeTests: XCTestCase {

    func testOpenAndCapabilitiesReadFromNativeLibrary() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "ok", maxSessions: 4),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        do {
            let capabilities = try await runtime.capabilities()
            XCTAssertEqual(capabilities.supportedEngines, ["fixture_engine"])
            XCTAssertEqual(
                Set(capabilities.supportedCapabilities),
                Set(["chat.completion", "audio.transcription", "audio.stt.batch", "audio.vad", "cache.introspect"])
            )
            XCTAssertEqual(capabilities.supportedArchs, ["darwin-arm64"])
            XCTAssertEqual(capabilities.ramTotalBytes, 16)
            XCTAssertEqual(capabilities.ramAvailableBytes, 8)
            XCTAssertTrue(capabilities.hasAppleSilicon)
            XCTAssertFalse(capabilities.hasCUDA)
            XCTAssertTrue(capabilities.hasMetal)
        } catch {
            await runtime.close()
            throw error
        }

        await runtime.close()
    }

    func testCacheIntrospectReadsNativeCacheAbi() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "ok", maxSessions: 4),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        do {
            let json = try await runtime.cacheIntrospect()
            let data = try XCTUnwrap(json.data(using: .utf8))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["version"] as? Int, 1)
            XCTAssertEqual(object["is_stub"] as? Bool, true)
            XCTAssertEqual((object["entries"] as? [Any])?.count, 0)
        } catch {
            await runtime.close()
            throw error
        }

        await runtime.close()
    }

    func testMissingNativeLibraryFailsClosed() async throws {
        let missingPath = "/tmp/octomil-runtime-missing-\(UUID().uuidString).dylib"

        do {
            _ = try await FFINativeRuntime.open(
                config: NativeRuntimeConfig(artifactRoot: "ok"),
                telemetrySink: nil,
                libraryPath: missingPath
            )
            XCTFail("Expected native runtime library load to fail closed.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .unsupported)
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertTrue(error.message?.contains(missingPath) == true)
        }
    }

    func testRuntimeOpenFailureCarriesThreadLastError() async throws {
        let libraryPath = try Self.buildFixtureDylib()

        do {
            _ = try await FFINativeRuntime.open(
                config: NativeRuntimeConfig(artifactRoot: "fail-open"),
                telemetrySink: nil,
                libraryPath: libraryPath
            )
            XCTFail("Expected oct_runtime_open failure to surface.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .internalError)
            XCTAssertEqual(error.sdkErrorCode, .inferenceFailed)
            XCTAssertTrue(error.message?.contains("fixture open failed") == true)
        }
    }

    func testRuntimeOpenOkWithNullHandleFailsClosed() async throws {
        let libraryPath = try Self.buildFixtureDylib()

        do {
            _ = try await FFINativeRuntime.open(
                config: NativeRuntimeConfig(artifactRoot: "null-handle"),
                telemetrySink: nil,
                libraryPath: libraryPath
            )
            XCTFail("Expected oct_runtime_open OK with NULL handle to fail closed.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .internalError)
            XCTAssertEqual(error.sdkErrorCode, .inferenceFailed)
            XCTAssertTrue(error.message?.contains("NULL runtime handle") == true)
        }
    }

    func testCapabilitiesFailureCarriesRuntimeLastError() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "fail-caps"),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        do {
            _ = try await runtime.capabilities()
            XCTFail("Expected oct_runtime_capabilities failure to surface.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .unsupported)
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertTrue(error.message?.contains("fixture capabilities unavailable") == true)
        }

        await runtime.close()
    }

    func testCapabilitiesVersionMismatchFailsClosed() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "bad-caps-version"),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        do {
            _ = try await runtime.capabilities()
            XCTFail("Expected capabilities version mismatch to fail closed.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .versionMismatch)
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertTrue(error.message?.contains("returned version 99") == true)
        }

        await runtime.close()
    }

    func testCapabilitiesNullArraysFailClosed() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "null-engines"),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        do {
            _ = try await runtime.capabilities()
            XCTFail("Expected NULL capabilities arrays to fail closed.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .internalError)
            XCTAssertEqual(error.sdkErrorCode, .inferenceFailed)
            XCTAssertTrue(error.message?.contains("NULL supported_engines") == true)
        }

        await runtime.close()
    }

    func testTelemetrySinkRejectedUntilEventBridgeLands() async throws {
        let sink: NativeTelemetrySink = { _ in }

        do {
            _ = try await FFINativeRuntime.open(
                config: NativeRuntimeConfig(artifactRoot: "ok"),
                telemetrySink: sink,
                libraryPath: "/tmp/unused-\(UUID().uuidString).dylib"
            )
            XCTFail("Expected telemetry sink to be rejected until event bridging is implemented.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .unsupported)
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertTrue(error.message?.contains("telemetry/event bridge is not implemented") == true)
        }
    }

    func testModelAndSessionBridgeParsesNativeEvents() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "ok"),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        try await model.warm()

        let session = try await runtime.openSession(
            config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
            model: model
        )

        try await session.sendText("hello")
        try await session.sendAudio(Data([0, 0, 0, 0]), sampleRate: 24000, channels: 1)

        var tags: [String] = []
        for try await event in await session.events(pollInterval: 0) {
            tags.append(Self.tag(for: event))
        }

        XCTAssertEqual(tags, [
            "started",
            "transcript",
            "transcript",
            "embedding",
            "audio",
            "vad",
            "diarization",
            "cache",
            "completed:ok",
        ])

        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testOperationsAfterCloseFailClosed() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "ok"),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        await runtime.close()
        await runtime.close()

        do {
            _ = try await runtime.capabilities()
            XCTFail("Expected capabilities after close to fail closed.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
            XCTAssertEqual(error.sdkErrorCode, .invalidInput)
            XCTAssertTrue(error.message?.contains("runtime is closed") == true)
        }
    }

    private static func buildFixtureDylib() throws -> String {
        let fileManager = FileManager.default
        let clangPath = "/usr/bin/clang"
        guard fileManager.isExecutableFile(atPath: clangPath) else {
            throw XCTSkip("clang is unavailable; cannot build native bridge fixture dylib")
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("octomil-ffi-fixture-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = directory.appendingPathComponent("fixture.c")
        let dylibURL = directory.appendingPathComponent("liboctomil_runtime_fixture.dylib")
        try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: clangPath)
        process.arguments = [
            "-dynamiclib",
            "-I",
            "/Users/seanb/Developer/Octomil/octomil-ios/Sources/COctomilRuntimeBridge/include",
            sourceURL.path,
            "-o",
            dylibURL.path,
        ]
        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "FFINativeRuntimeTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "fixture dylib compile failed: \(stderrText)"]
            )
        }

        return dylibURL.path
    }

    private static func tag(for event: NativeEvent) -> String {
        switch event {
        case .sessionStarted: return "started"
        case .transcriptChunk: return "transcript"
        case .transcriptSegment: return "transcript"
        case .transcriptFinal: return "transcript"
        case .embeddingVector: return "embedding"
        case .vadTransition: return "vad"
        case .diarizationSegment: return "diarization"
        case .ttsAudioChunk: return "audio"
        case .cacheHit: return "cache"
        case .cacheMiss: return "cache"
        case .turnEnded: return "turnEnded"
        case .audioChunk: return "audio"
        case .sessionCompleted(let payload, _): return "completed:\(payload.terminalStatus)"
        case .error: return "error"
        case .modelLoaded: return "modelLoaded"
        }
    }
}

private actor FFIFakeNativeModel: NativeModel {
    func warm() async throws {}
    func evict() async throws {}
    func close() async throws {}
}

private let fixtureSource = """
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "COctomilRuntimeBridge.h"

struct oct_runtime {
    int fail_caps;
    int bad_caps_version;
    int null_engines;
    char last_error[256];
};

static char g_thread_error[256] = "";
static const char* g_engines[] = {"fixture_engine", NULL};
static const char* g_capabilities[] = {"chat.completion", "audio.transcription", "audio.stt.batch", "audio.vad", "cache.introspect", NULL};
static const char* g_archs[] = {"darwin-arm64", NULL};

static void set_error(char* destination, const char* message) {
    if (destination == NULL) return;
    snprintf(destination, 256, "%s", message == NULL ? "" : message);
}

static int copy_error(const char* source, char* buffer, size_t buflen) {
    if (buffer == NULL || buflen == 0) return -1;
    const char* message = source == NULL ? "" : source;
    size_t n = strlen(message);
    if (n >= buflen) n = buflen - 1;
    memcpy(buffer, message, n);
    buffer[n] = '\\0';
    return (int)n;
}

uint32_t oct_runtime_abi_version_major(void) { return 0u; }
uint32_t oct_runtime_abi_version_minor(void) { return 10u; }
size_t oct_runtime_config_size(void) { return sizeof(oct_runtime_config_t); }
size_t oct_capabilities_size(void) { return sizeof(oct_capabilities_t); }

oct_status_t oct_runtime_open(const oct_runtime_config_t* config, oct_runtime_t** out) {
    if (out == NULL) {
        set_error(g_thread_error, "fixture out is null");
        return OCT_STATUS_INVALID_INPUT;
    }
    *out = NULL;
    if (config == NULL) {
        set_error(g_thread_error, "fixture config is null");
        return OCT_STATUS_INVALID_INPUT;
    }
    if (config->version != 1u) {
        set_error(g_thread_error, "fixture version mismatch");
        return OCT_STATUS_VERSION_MISMATCH;
    }
    if (config->artifact_root != NULL && strcmp(config->artifact_root, "fail-open") == 0) {
        set_error(g_thread_error, "fixture open failed");
        return OCT_STATUS_INTERNAL;
    }
    if (config->artifact_root != NULL && strcmp(config->artifact_root, "null-handle") == 0) {
        set_error(g_thread_error, "fixture null handle");
        return OCT_STATUS_OK;
    }

    oct_runtime_t* runtime = (oct_runtime_t*)calloc(1, sizeof(struct oct_runtime));
    if (runtime == NULL) {
        set_error(g_thread_error, "fixture allocation failed");
        return OCT_STATUS_INTERNAL;
    }
    runtime->fail_caps = config->artifact_root != NULL && strcmp(config->artifact_root, "fail-caps") == 0;
    runtime->bad_caps_version = config->artifact_root != NULL && strcmp(config->artifact_root, "bad-caps-version") == 0;
    runtime->null_engines = config->artifact_root != NULL && strcmp(config->artifact_root, "null-engines") == 0;
    set_error(runtime->last_error, "");
    *out = runtime;
    return OCT_STATUS_OK;
}

void oct_runtime_close(oct_runtime_t* runtime) {
    free(runtime);
}

oct_status_t oct_runtime_capabilities(oct_runtime_t* runtime, oct_capabilities_t* out) {
    if (runtime == NULL || out == NULL) {
        return OCT_STATUS_INVALID_INPUT;
    }
    if (runtime->fail_caps) {
        set_error(runtime->last_error, "fixture capabilities unavailable");
        return OCT_STATUS_UNSUPPORTED;
    }

    const size_t header_min = offsetof(oct_capabilities_t, supported_engines);
    if (out->size < header_min) {
        set_error(runtime->last_error, "fixture capabilities buffer too small");
        return OCT_STATUS_INVALID_INPUT;
    }

    const size_t caller_size = out->size;
    oct_capabilities_t staged;
    memset(&staged, 0, sizeof(staged));
    staged.version = runtime->bad_caps_version ? 99u : 1u;
    staged.size = caller_size;
    staged.supported_engines = runtime->null_engines ? NULL : g_engines;
    staged.supported_capabilities = g_capabilities;
    staged.supported_archs = g_archs;
    staged.ram_total_bytes = 16u;
    staged.ram_available_bytes = 8u;
    staged.has_apple_silicon = 1u;
    staged.has_cuda = 0u;
    staged.has_metal = 1u;

    const size_t copy_n = caller_size < sizeof(staged) ? caller_size : sizeof(staged);
    memcpy(out, &staged, copy_n);
    return OCT_STATUS_OK;
}

void oct_runtime_capabilities_free(oct_capabilities_t* caps) {
    if (caps == NULL) return;
    const size_t buffer_size = caps->size;
    if (buffer_size > 0 && buffer_size <= sizeof(*caps)) {
        memset(caps, 0, buffer_size);
    }
}

int oct_runtime_last_error(oct_runtime_t* runtime, char* buffer, size_t buflen) {
    if (runtime == NULL) return -1;
    return copy_error(runtime->last_error, buffer, buflen);
}

int oct_last_thread_error(char* buffer, size_t buflen) {
    return copy_error(g_thread_error, buffer, buflen);
}

size_t oct_model_config_size(void) { return sizeof(oct_model_config_t); }
size_t oct_session_config_size(void) { return sizeof(oct_session_config_t); }
size_t oct_audio_view_size(void) { return sizeof(oct_audio_view_t); }
size_t oct_event_size(void) { return sizeof(oct_event_t); }

struct oct_model {
    oct_runtime_t* runtime;
    int warmed;
    int session_count;
    int closed;
    char model_uri[256];
};

struct oct_session {
    oct_runtime_t* runtime;
    oct_model_t* model;
    int index;
    int closed;
    char capability[64];
};

static const char* kSessionStartedEngine = "fixture_engine";
static const char* kSessionStartedModelDigest = "sha256:fixture";
static const char* kSessionStartedLocality = "on-device";
static const char* kSessionStartedStreamingMode = "streaming";
static const char* kSessionStartedRuntimeBuildTag = "fixture-build";
static const char* kTranscriptChunk = "hello ";
static const char* kTranscriptSegment = "world";
static const char* kCacheLayer = "kv-prefix";
static const char* kDiarizationLabel = "SPEAKER_07";
static const char* kTtsPcmBytes = "ABCD";
static const float kEmbeddingValues[] = {0.25f, 0.75f};
static const uint8_t kTtsPcmBuffer[] = {0x01, 0x02, 0x03, 0x04};

oct_status_t oct_model_open(oct_runtime_t* runtime_ptr, const oct_model_config_t* config, oct_model_t** out_model) {
    if (runtime_ptr == NULL || config == NULL || out_model == NULL) {
        set_error(g_thread_error, "fixture model open invalid input");
        return OCT_STATUS_INVALID_INPUT;
    }
    *out_model = NULL;
    if (config->version != OCT_MODEL_CONFIG_VERSION) {
        set_error(g_thread_error, "fixture model version mismatch");
        return OCT_STATUS_VERSION_MISMATCH;
    }

    oct_model_t* model = (oct_model_t*)calloc(1, sizeof(struct oct_model));
    if (model == NULL) {
        set_error(g_thread_error, "fixture model allocation failed");
        return OCT_STATUS_INTERNAL;
    }
    model->runtime = runtime_ptr;
    if (config->model_uri != NULL) {
        snprintf(model->model_uri, sizeof(model->model_uri), "%s", config->model_uri);
    }
    *out_model = model;
    return OCT_STATUS_OK;
}

oct_status_t oct_model_warm(oct_model_t* model) {
    if (model == NULL || model->closed) return OCT_STATUS_INVALID_INPUT;
    model->warmed = 1;
    return OCT_STATUS_OK;
}

oct_status_t oct_model_evict(oct_model_t* model) {
    if (model == NULL || model->closed) return OCT_STATUS_INVALID_INPUT;
    model->warmed = 0;
    return OCT_STATUS_OK;
}

oct_status_t oct_model_close(oct_model_t* model) {
    if (model == NULL) return OCT_STATUS_INVALID_INPUT;
    if (model->closed) return OCT_STATUS_INVALID_INPUT;
    if (model->session_count > 0) {
        return OCT_STATUS_BUSY;
    }
    model->closed = 1;
    free(model);
    return OCT_STATUS_OK;
}

oct_status_t oct_session_open(oct_runtime_t* runtime_ptr, const oct_session_config_t* config, oct_session_t** out) {
    if (runtime_ptr == NULL || config == NULL || out == NULL || config->model == NULL) {
        set_error(g_thread_error, "fixture session open invalid input");
        return OCT_STATUS_INVALID_INPUT;
    }
    *out = NULL;
    oct_session_t* session = (oct_session_t*)calloc(1, sizeof(struct oct_session));
    if (session == NULL) {
        set_error(g_thread_error, "fixture session allocation failed");
        return OCT_STATUS_INTERNAL;
    }
    session->runtime = runtime_ptr;
    session->model = config->model;
    session->model->session_count += 1;
    if (config->capability != NULL) {
        snprintf(session->capability, sizeof(session->capability), "%s", config->capability);
    }
    *out = session;
    return OCT_STATUS_OK;
}

void oct_session_close(oct_session_t* session) {
    if (session == NULL) return;
    if (!session->closed) {
        session->closed = 1;
        if (session->model != NULL && session->model->session_count > 0) {
            session->model->session_count -= 1;
        }
        free(session);
    }
}

oct_status_t oct_session_send_audio(oct_session_t* session, const oct_audio_view_t* audio) {
    (void)session;
    (void)audio;
    return OCT_STATUS_OK;
}

oct_status_t oct_session_send_text(oct_session_t* session, const char* utf8) {
    (void)session;
    (void)utf8;
    return OCT_STATUS_OK;
}

oct_status_t oct_session_poll_event(oct_session_t* session, oct_event_t* out, uint32_t timeout_ms) {
    (void)timeout_ms;
    if (session == NULL || out == NULL || session->closed) {
        return OCT_STATUS_INVALID_INPUT;
    }
    memset(out, 0, sizeof(*out));
    out->version = OCT_EVENT_VERSION;
    out->size = sizeof(*out);
    switch (session->index++) {
        case 0:
            out->type = OCT_EVENT_SESSION_STARTED;
            out->data.session_started.engine = kSessionStartedEngine;
            out->data.session_started.model_digest = kSessionStartedModelDigest;
            out->data.session_started.locality = kSessionStartedLocality;
            out->data.session_started.streaming_mode = kSessionStartedStreamingMode;
            out->data.session_started.runtime_build_tag = kSessionStartedRuntimeBuildTag;
            break;
        case 1:
            out->type = OCT_EVENT_TRANSCRIPT_CHUNK;
            out->data.transcript_chunk.utf8 = kTranscriptChunk;
            out->data.transcript_chunk.n_bytes = (uint32_t)strlen(kTranscriptChunk);
            break;
        case 2:
            out->type = OCT_EVENT_TRANSCRIPT_SEGMENT;
            out->data.transcript_segment.utf8 = kTranscriptSegment;
            out->data.transcript_segment.n_bytes = (uint32_t)strlen(kTranscriptSegment);
            out->data.transcript_segment.start_ms = 10;
            out->data.transcript_segment.end_ms = 20;
            out->data.transcript_segment.segment_index = 0;
            out->data.transcript_segment.is_final = 1;
            break;
        case 3:
            out->type = OCT_EVENT_EMBEDDING_VECTOR;
            out->data.embedding_vector.values = kEmbeddingValues;
            out->data.embedding_vector.n_dim = 2;
            out->data.embedding_vector.n_input_tokens = 7;
            out->data.embedding_vector.index = 0;
            out->data.embedding_vector.pooling_type = 1;
            out->data.embedding_vector.is_normalized = 1;
            break;
        case 4:
            out->type = OCT_EVENT_TTS_AUDIO_CHUNK;
            out->data.tts_audio_chunk.pcm = kTtsPcmBuffer;
            out->data.tts_audio_chunk.n_bytes = sizeof(kTtsPcmBuffer);
            out->data.tts_audio_chunk.sample_rate = 24000;
            out->data.tts_audio_chunk.sample_format = OCT_SAMPLE_FORMAT_PCM_F32LE;
            out->data.tts_audio_chunk.channels = 1;
            out->data.tts_audio_chunk.is_final = 1;
            break;
        case 5:
            out->type = OCT_EVENT_VAD_TRANSITION;
            out->data.vad_transition.transition_kind = 1;
            out->data.vad_transition.timestamp_ms = 123;
            out->data.vad_transition.confidence = 0.99f;
            break;
        case 6:
            out->type = OCT_EVENT_DIARIZATION_SEGMENT;
            out->data.diarization_segment.start_ms = 30;
            out->data.diarization_segment.end_ms = 70;
            out->data.diarization_segment.speaker_id = 7;
            out->data.diarization_segment.speaker_label = kDiarizationLabel;
            break;
        case 7:
            out->type = OCT_EVENT_CACHE_HIT;
            out->data.cache.layer = kCacheLayer;
            out->data.cache.saved_tokens = 12;
            break;
        default:
            out->type = OCT_EVENT_SESSION_COMPLETED;
            out->data.session_completed.setup_ms = 1.0f;
            out->data.session_completed.engine_first_chunk_ms = 2.0f;
            out->data.session_completed.e2e_first_chunk_ms = 3.0f;
            out->data.session_completed.total_latency_ms = 4.0f;
            out->data.session_completed.queued_ms = 0.0f;
            out->data.session_completed.observed_chunks = 8;
            out->data.session_completed.capability_verified = 1;
            out->data.session_completed.terminal_status = OCT_STATUS_OK;
            session->index = 999;
            break;
    }
    return OCT_STATUS_OK;
}

oct_status_t oct_session_cancel(oct_session_t* session) {
    (void)session;
    return OCT_STATUS_OK;
}

oct_status_t oct_runtime_cache_clear_all(oct_runtime_t* runtime) {
    (void)runtime;
    return OCT_STATUS_UNSUPPORTED;
}

oct_status_t oct_runtime_cache_clear_capability(oct_runtime_t* runtime, const char* capability_id) {
    (void)runtime;
    (void)capability_id;
    return OCT_STATUS_UNSUPPORTED;
}

oct_status_t oct_runtime_cache_clear_scope(oct_runtime_t* runtime, uint32_t scope_id) {
    (void)runtime;
    (void)scope_id;
    return OCT_STATUS_UNSUPPORTED;
}

oct_status_t oct_runtime_cache_introspect(oct_runtime_t* runtime, char* out_json_buf, size_t buf_len) {
    (void)runtime;
    return copy_error("{\\\"version\\\":1,\\\"is_stub\\\":true,\\\"entries\\\":[]}", out_json_buf, buf_len) >= 0
        ? OCT_STATUS_OK
        : OCT_STATUS_INVALID_INPUT;
}
"""
#endif

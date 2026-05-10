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
            XCTAssertEqual(capabilities.supportedCapabilities, ["chat.completion", "audio.vad"])
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

    func testModelAndSessionBridgeRemainFailClosed() async throws {
        let libraryPath = try Self.buildFixtureDylib()
        let runtime = try await FFINativeRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "ok"),
            telemetrySink: nil,
            libraryPath: libraryPath
        )

        do {
            _ = try await runtime.openModel(
                config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
            )
            XCTFail("Expected model bridge to remain unsupported.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .unsupported)
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertTrue(error.message?.contains("model bridge is not implemented") == true)
        }

        do {
            _ = try await runtime.openSession(
                config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
                model: FFIFakeNativeModel()
            )
            XCTFail("Expected session bridge to remain unsupported.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .unsupported)
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertTrue(error.message?.contains("session/event bridge is not implemented") == true)
        }

        await runtime.close()
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

typedef uint32_t oct_status_t;
#define OCT_STATUS_OK 0u
#define OCT_STATUS_INVALID_INPUT 1u
#define OCT_STATUS_UNSUPPORTED 2u
#define OCT_STATUS_INTERNAL 7u
#define OCT_STATUS_VERSION_MISMATCH 8u

typedef void (*oct_telemetry_sink_fn)(const void* event, void* user_data);

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

typedef struct {
    int fail_caps;
    char last_error[256];
} oct_runtime_t;

static char g_thread_error[256] = "";
static const char* g_engines[] = {"fixture_engine", NULL};
static const char* g_capabilities[] = {"chat.completion", "audio.vad", NULL};
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
uint32_t oct_runtime_abi_version_minor(void) { return 9u; }
size_t oct_runtime_config_size(void) { return sizeof(oct_runtime_config_t); }
size_t oct_capabilities_size(void) { return sizeof(oct_capabilities_t); }

oct_status_t oct_runtime_open(const oct_runtime_config_t* config, void** out) {
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

    oct_runtime_t* runtime = (oct_runtime_t*)calloc(1, sizeof(oct_runtime_t));
    if (runtime == NULL) {
        set_error(g_thread_error, "fixture allocation failed");
        return OCT_STATUS_INTERNAL;
    }
    runtime->fail_caps = config->artifact_root != NULL && strcmp(config->artifact_root, "fail-caps") == 0;
    set_error(runtime->last_error, "");
    *out = runtime;
    return OCT_STATUS_OK;
}

void oct_runtime_close(void* runtime) {
    free(runtime);
}

oct_status_t oct_runtime_capabilities(void* runtime_ptr, oct_capabilities_t* out) {
    oct_runtime_t* runtime = (oct_runtime_t*)runtime_ptr;
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
    staged.version = 1u;
    staged.size = caller_size;
    staged.supported_engines = g_engines;
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

int oct_runtime_last_error(void* runtime_ptr, char* buffer, size_t buflen) {
    oct_runtime_t* runtime = (oct_runtime_t*)runtime_ptr;
    if (runtime == NULL) return -1;
    return copy_error(runtime->last_error, buffer, buflen);
}

int oct_last_thread_error(char* buffer, size_t buflen) {
    return copy_error(g_thread_error, buffer, buflen);
}
"""
#endif

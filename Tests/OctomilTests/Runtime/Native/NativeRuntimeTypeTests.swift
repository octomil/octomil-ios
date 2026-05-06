import Foundation
import XCTest
@testable import Octomil

final class NativeRuntimeTypeTests: XCTestCase {

    // Exercises every case of `NativeEvent.envelope`. The stub never fires
    // .error or .modelLoaded through the events() stream, so tests that
    // pattern-match on cases miss those branches; this hits the accessor
    // directly for all seven.
    func testEventEnvelopeAccessorCoversAllCases() {
        let env = NativeOperationalEnvelope(
            requestID: "req-1",
            routeID: "route-1",
            traceID: "trace-1",
            engineVersion: "v",
            adapterVersion: "v",
            accelerator: "metal",
            artifactDigest: "sha256:x",
            cacheWasHit: true
        )
        let started = NativeSessionStartedPayload(
            engine: "e", modelDigest: "d", locality: "on-device",
            streamingMode: "streaming", runtimeBuildTag: "t"
        )
        let audio = NativeAudioChunkPayload(
            pcm: Data([0, 1, 2, 3]), sampleRate: 24000,
            sampleFormat: .pcmF32LE, channels: 1, isFinal: true
        )
        let transcript = NativeTranscriptChunkPayload(utf8: "hi")
        let errorPayload = NativeErrorPayload(code: "E_INTERNAL", message: "boom", errorCode: 42)
        let completed = NativeSessionCompletedPayload(
            setupMs: 1, engineFirstChunkMs: 2, e2eFirstChunkMs: 3,
            totalLatencyMs: 4, queuedMs: 0, observedChunks: 5,
            capabilityVerified: true, terminalStatus: .ok
        )
        let loaded = NativeModelLoadedPayload(
            engine: "e", modelID: "m", artifactDigest: "d",
            loadMs: 10, warmMs: 5, policyPreset: "default", source: "stub"
        )

        let cases: [NativeEvent] = [
            .sessionStarted(started, envelope: env),
            .audioChunk(audio, envelope: env),
            .transcriptChunk(transcript, envelope: env),
            .turnEnded(envelope: env),
            .error(errorPayload, envelope: env),
            .sessionCompleted(completed, envelope: env),
            .modelLoaded(loaded, envelope: env),
        ]
        for event in cases {
            XCTAssertEqual(event.envelope.requestID, "req-1")
            XCTAssertEqual(event.envelope.artifactDigest, "sha256:x")
            XCTAssertTrue(event.envelope.cacheWasHit)
        }
    }

    func testNativeRuntimeErrorDefaultMessageIsNil() {
        let error = NativeRuntimeError(status: .timeout)
        XCTAssertEqual(error.status, .timeout)
        XCTAssertNil(error.message)
    }

    func testNativeOperationalEnvelopeDefaultInit() {
        let env = NativeOperationalEnvelope()
        XCTAssertEqual(env.requestID, "")
        XCTAssertEqual(env.routeID, "")
        XCTAssertEqual(env.traceID, "")
        XCTAssertEqual(env.engineVersion, "")
        XCTAssertEqual(env.adapterVersion, "")
        XCTAssertEqual(env.accelerator, "")
        XCTAssertEqual(env.artifactDigest, "")
        XCTAssertFalse(env.cacheWasHit)
    }

    func testNativeABIPinnedVersion() {
        XCTAssertEqual(NativeABI.requiredMajor, 0)
        XCTAssertEqual(NativeABI.requiredMinor, 7)
    }

    func testNativeErrorPayloadInit() {
        let payload = NativeErrorPayload(code: "E_BUSY", message: "busy", errorCode: 4)
        XCTAssertEqual(payload.code, "E_BUSY")
        XCTAssertEqual(payload.message, "busy")
        XCTAssertEqual(payload.errorCode, 4)
    }
}

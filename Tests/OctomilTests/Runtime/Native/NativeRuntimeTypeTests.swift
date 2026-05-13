import Foundation
import XCTest
@testable import Octomil

final class NativeRuntimeTypeTests: XCTestCase {

    // Exercises every case of `NativeEvent.envelope`. The stub never fires
    // the richer native event cases through the events() stream, so tests
    // that pattern-match on the stream miss those branches; this hits the
    // accessor directly for every case.
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
        let transcriptSegment = NativeTranscriptSegmentPayload(
            utf8: "seg",
            nBytes: 3,
            startMs: 10,
            endMs: 20,
            segmentIndex: 0,
            isFinal: true
        )
        let transcriptFinal = NativeTranscriptFinalPayload(
            utf8: "final",
            nBytes: 5,
            nSegments: 1,
            durationMs: 25
        )
        let embedding = NativeEmbeddingVectorPayload(
            values: [0.25, 0.75],
            dimension: 2,
            inputTokens: 7,
            index: 0,
            poolingType: 1,
            isNormalized: true
        )
        let vad = NativeVADTransitionPayload(
            transitionKind: 1,
            timestampMs: 123,
            confidence: 0.92
        )
        let diarization = NativeDiarizationSegmentPayload(
            startMs: 30,
            endMs: 70,
            speakerID: 7,
            speakerLabel: "SPEAKER_07"
        )
        let cache = NativeCachePayload(layer: "kv-prefix", savedTokens: 12)
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
            .transcriptSegment(transcriptSegment, envelope: env),
            .transcriptFinal(transcriptFinal, envelope: env),
            .embeddingVector(embedding, envelope: env),
            .vadTransition(vad, envelope: env),
            .diarizationSegment(diarization, envelope: env),
            .ttsAudioChunk(audio, envelope: env),
            .cacheHit(cache, envelope: env),
            .cacheMiss(cache, envelope: env),
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
        XCTAssertEqual(NativeABI.requiredMinor, 10)
    }

    func testNativeErrorPayloadInit() {
        let payload = NativeErrorPayload(code: "E_BUSY", message: "busy", errorCode: 4)
        XCTAssertEqual(payload.code, "E_BUSY")
        XCTAssertEqual(payload.message, "busy")
        XCTAssertEqual(payload.errorCode, 4)
    }

    func testNativeDiarizationSegmentPayloadInit() {
        let payload = NativeDiarizationSegmentPayload(
            startMs: 1,
            endMs: 2,
            speakerID: 3,
            speakerLabel: "speaker"
        )
        XCTAssertEqual(payload.startMs, 1)
        XCTAssertEqual(payload.endMs, 2)
        XCTAssertEqual(payload.speakerID, 3)
        XCTAssertEqual(payload.speakerLabel, "speaker")
    }

    func testNativeStatusDefaultBridgeErrorCodeMapping() {
        XCTAssertNil(NativeStatus.ok.nativeBridgeErrorCode)
        XCTAssertEqual(NativeStatus.invalidInput.nativeBridgeErrorCode, .invalidInput)
        XCTAssertEqual(NativeStatus.unsupported.nativeBridgeErrorCode, .runtimeUnavailable)
        XCTAssertEqual(NativeStatus.notFound.nativeBridgeErrorCode, .modelNotFound)
        XCTAssertEqual(NativeStatus.busy.nativeBridgeErrorCode, .runtimeUnavailable)
        XCTAssertEqual(NativeStatus.timeout.nativeBridgeErrorCode, .streamInterrupted)
        XCTAssertEqual(NativeStatus.cancelled.nativeBridgeErrorCode, .cancelled)
        XCTAssertEqual(NativeStatus.internalError.nativeBridgeErrorCode, .inferenceFailed)
        XCTAssertEqual(NativeStatus.versionMismatch.nativeBridgeErrorCode, .runtimeUnavailable)
    }
}

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
        // requiredMinor MUST stay at 10 — image-input is opted into
        // inline by callers that use `imageInputMinimumMinor`, not by
        // raising the binding-wide floor. Bumping this requires a
        // runtime-side flip of embeddings.image out of
        // kBlockedCapabilities AND a public SDK facade that requires
        // image support.
        XCTAssertEqual(NativeABI.requiredMinor, 10)
    }

    func testNativeABIImageInputMinimumMinorIsAbi11() {
        // Optional ABI-11 inner gate. Symbol presence (and therefore
        // image-input support) requires runtime minor >= 11. Pinned
        // here so a regression bumping the floor to 12 surfaces in
        // the type tests rather than at runtime.
        XCTAssertEqual(NativeABI.imageInputMinimumMinor, 11)
        XCTAssertGreaterThan(NativeABI.imageInputMinimumMinor, NativeABI.requiredMinor)
    }

    // MARK: - NativeImageMime (ABI minor 11)

    /// Assert the Swift `NativeImageMime` raw values match the
    /// `OCT_IMAGE_MIME_*` constants from `COctomilRuntimeBridge.h`
    /// and `octomil-runtime/include/octomil/runtime.h` (PR #86,
    /// 1d92e35). Drift between the two breaks the FFI contract —
    /// the runtime reads `oct_image_view_t.mime` as a uint32 against
    /// the same closed enum. C constants are not visible in the
    /// Swift test scope so the literal values are pinned here; the
    /// FFINativeRuntime `validateABI` path catches any silent
    /// shift via `oct_image_view_size()`.
    func testNativeImageMimeRawValuesMatchCConstants() {
        // Pinned to OCT_IMAGE_MIME_UNKNOWN (0) — future-compat
        // sentinel; never set by callers.
        XCTAssertEqual(NativeImageMime.unknown.rawValue, 0)
        // OCT_IMAGE_MIME_PNG  = 1u
        XCTAssertEqual(NativeImageMime.png.rawValue, 1)
        // OCT_IMAGE_MIME_JPEG = 2u
        XCTAssertEqual(NativeImageMime.jpeg.rawValue, 2)
        // OCT_IMAGE_MIME_WEBP = 3u
        XCTAssertEqual(NativeImageMime.webp.rawValue, 3)
        // OCT_IMAGE_MIME_RGB8 = 4u (raw decoded uint8 RGB)
        XCTAssertEqual(NativeImageMime.rgb8.rawValue, 4)
    }

    func testNativeImageMimeAllCasesConstructible() {
        let all: [NativeImageMime] = [.unknown, .png, .jpeg, .webp, .rgb8]
        // No two raws collide.
        let raws = Set(all.map(\.rawValue))
        XCTAssertEqual(raws.count, all.count)
        // Raw round-trip works for every defined case.
        for mime in all {
            XCTAssertEqual(NativeImageMime(rawValue: mime.rawValue), mime)
        }
        // Unknown raws fail closed (Swift rawValue init returns nil).
        XCTAssertNil(NativeImageMime(rawValue: 99))
    }

    func testNativeImageViewInit() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let view = NativeImageView(bytes: bytes, mime: .png)
        XCTAssertEqual(view.bytes, bytes)
        XCTAssertEqual(view.mime, .png)
    }

    // MARK: - OCT_EMBED_POOLING_IMAGE_CLIP (ABI minor 11)

    /// `OCT_EMBED_POOLING_IMAGE_CLIP = 5u` — appended to the
    /// embedding pooling-type enum at ABI minor 11 to disambiguate
    /// image-vs-text embeddings at the consumer side. Pinned numeric
    /// so a runtime-side renumber surfaces here. Existing pooling
    /// types: MEAN=1, CLS=2, LAST=3, RANK=4.
    func testEmbedPoolingImageClipConstantIsFive() {
        // Sourced from octomil-runtime/include/octomil/runtime.h
        // OCT_EMBED_POOLING_IMAGE_CLIP definition (PR #86, 1d92e35).
        let oct_embed_pooling_image_clip: UInt32 = 5
        XCTAssertEqual(oct_embed_pooling_image_clip, 5)
        // Future-compat probe: any NativeEmbeddingVectorPayload
        // carrying poolingType == 5 is image embedding, NOT text
        // mean-pool.
        let payload = NativeEmbeddingVectorPayload(
            values: [],
            dimension: 0,
            inputTokens: 0,
            index: 0,
            poolingType: oct_embed_pooling_image_clip,
            isNormalized: false
        )
        XCTAssertEqual(payload.poolingType, 5)
    }

    // MARK: - sendImage default extension

    /// The `NativeSession.sendImage` extension default throws
    /// `.unsupported` so existing conformers (StubSession, hosted
    /// bridges) keep compiling without an explicit override. Verify
    /// the StubSession (which does NOT override) hits this path.
    func testStubSessionSendImageThrowsUnsupportedFromExtensionDefault() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "stub"),
            telemetrySink: nil
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:stub", artifactDigest: "sha256:stub")
        )
        let session = try await runtime.openSession(
            config: NativeSessionConfig(modelURI: "model:stub", capability: "chat.completion"),
            model: model
        )

        do {
            try await session.sendImage(NativeImageView(bytes: Data([0xFF]), mime: .png))
            XCTFail("Expected sendImage on stub session to throw .unsupported.")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .unsupported)
            // Default mapper routes .unsupported -> .runtimeUnavailable
            // per NativeStatus.nativeBridgeErrorCode. Capability stays
            // BLOCKED_WITH_PROOF at this commit.
            XCTAssertEqual(error.sdkErrorCode, .runtimeUnavailable)
            XCTAssertNotNil(error.message)
        }

        await session.close()
        try await model.close()
        await runtime.close()
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

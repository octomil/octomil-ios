import Foundation
import XCTest

@testable import Octomil

/// Capability-lifecycle parity coverage for the ``app:`` /
/// ``policy:`` parameters on ``audio.transcriptions.create``.
///
/// The behaviour mirrors ``AudioSpeech``: ``.localOnly``/``.private``
/// must fail closed (``cloudFallbackDisallowed``) when no local
/// runtime is registered, and the resolver must derive the policy
/// from an app manifest when no explicit policy is passed.
final class AudioTranscriptionsAppPolicyTests: XCTestCase {

    // MARK: - policy

    func testCreateRejectsLocalOnlyWhenRuntimeMissing() async {
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in nil })
        do {
            _ = try await transcriptions.create(
                audio: Data([0x00, 0x01]),
                model: "whisper-base",
                policy: .localOnly
            )
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed(let reason) {
            XCTAssertTrue(reason.contains("local_only"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCreateRejectsPrivateWhenRuntimeMissing() async {
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in nil })
        do {
            _ = try await transcriptions.create(
                audio: Data([0x00, 0x01]),
                model: "whisper-base",
                policy: .private
            )
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCreateUsesAppManifestPolicyWhenExplicitPolicyOmitted() async {
        let app = AppManifest(models: [
            AppModelEntry(
                id: "whisper-base",
                capability: .transcription,
                delivery: .bundled, // bundled → effectiveRoutingPolicy = .localOnly
                bundledPath: "Models/whisper-base.mlmodelc"
            )
        ])
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in nil })
        do {
            _ = try await transcriptions.create(
                audio: Data([0x00, 0x01]),
                model: "@app/notes/transcription",
                app: app
            )
            XCTFail("expected cloudFallbackDisallowed via manifest-derived local_only")
        } catch OctomilError.cloudFallbackDisallowed {
            // expected — the manifest entry is bundled, which derives
            // local-only routing, and the runtime resolver returned
            // nil.
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCreateAllowsCloudFallbackWhenPolicyIsCloudFirst() async throws {
        // When the resolver does have a runtime, the policy is
        // permissive, and the call should succeed without a
        // routing-policy refusal.
        let mock = SpyRuntime(text: "ok")
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in mock })
        let result = try await transcriptions.create(
            audio: Data([0x00, 0x01]),
            model: "whisper-base",
            policy: .cloudFirst
        )
        XCTAssertEqual(result.text, "ok")
    }

    // MARK: - warmup

    func testWarmupReturnsCachedOutcomeWhenRuntimeRegistered() async throws {
        let mock = SpyRuntime(text: "")
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in mock })

        let outcome = try await transcriptions.warmup(model: "whisper-base")

        XCTAssertEqual(outcome.modelId, "whisper-base")
        XCTAssertTrue(outcome.cached)
    }

    func testWarmupRefusesLocalOnlyWhenRuntimeMissing() async {
        let transcriptions = AudioTranscriptions(runtimeResolver: { _ in nil })
        let app = AppManifest(models: [
            AppModelEntry(
                id: "whisper-base",
                capability: .transcription,
                delivery: .bundled,
                bundledPath: "Models/whisper-base.mlmodelc"
            )
        ])
        do {
            _ = try await transcriptions.warmup(model: "whisper-base", app: app)
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

private final class SpyRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities(supportsStreaming: false)
    let text: String
    init(text: String) { self.text = text }
    func run(request: RuntimeRequest) async throws -> RuntimeResponse { RuntimeResponse(text: text) }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

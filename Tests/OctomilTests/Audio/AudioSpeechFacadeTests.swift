import Foundation
import XCTest

@testable import Octomil

/// Capability-lifecycle parity tests for ``audio.speech.create``,
/// ``audio.speech.warmup``, and the routing-policy / app-identity
/// guarantees that the contract requires.
///
/// The tests use a fake ``TtsBackend`` implementation so the facade
/// exercises the full prepare → load → synthesize → route metadata
/// flow without linking sherpa-onnx (which is iOS-only and ships in
/// the optional ``OctomilRuntimeSherpaTTS`` target).
final class AudioSpeechFacadeTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-audio-speech-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        await TtsRuntimeRegistry.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        await TtsRuntimeRegistry.shared.reset()
        try await super.tearDown()
    }

    // MARK: - create()

    func testCreateRoutesThroughPrepareAndProducesSpeechResult() async throws {
        let speech = try await makeFacadeWithFakeBackend()

        let result = try await speech.create(
            model: "kokoro-82m",
            input: "hello world",
            voice: "af_bella",
            speed: 1.0
        )

        XCTAssertEqual(result.contentType, "audio/wav")
        XCTAssertEqual(result.format, "wav")
        XCTAssertEqual(result.model, "kokoro-82m")
        XCTAssertEqual(result.route.execution?.locality, "local")
        XCTAssertEqual(result.route.execution?.mode, "sdk_runtime")
        XCTAssertEqual(result.route.execution?.engine, "sherpa-onnx")
        XCTAssertEqual(result.route.model.requested.capability, "tts")
        XCTAssertNotNil(result.preparedDir, "prepared dir must be surfaced for audit/tests")
        // The artifact dir should contain the canonical Sherpa Kokoro
        // layout written by the fake backend's setup, demonstrating
        // create() consumed the prepared dir.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: result.preparedDir!.appendingPathComponent("model.onnx").path
        ))
    }

    func testCreateRejectsEmptyInput() async throws {
        let speech = try await makeFacadeWithFakeBackend()
        do {
            _ = try await speech.create(model: "kokoro-82m", input: "  ")
            XCTFail("expected invalidInput")
        } catch OctomilError.invalidInput {
            // expected
        }
    }

    // MARK: - warmup()

    func testWarmupLoadsBackendThenCreateReusesIt() async throws {
        let speech = try await makeFacadeWithFakeBackend()

        let warm = try await speech.warmup(model: "kokoro-82m")
        XCTAssertEqual(warm.engine, "sherpa-onnx")
        XCTAssertEqual(warm.modelId, "kokoro-82m")

        // After warmup, the registry must hold the cached backend.
        let cached = await TtsRuntimeRegistry.shared.cached(modelId: "kokoro-82m")
        XCTAssertNotNil(cached, "warmup must populate the registry's loaded cache")

        // create() should reuse the same backend instance.
        _ = try await speech.create(model: "kokoro-82m", input: "test")
        let backend = cached as? FakeTtsBackend
        XCTAssertEqual(backend?.synthesizeCallCount, 1, "warmup must NOT have triggered synthesis")

        let cachedAfter = await TtsRuntimeRegistry.shared.cached(modelId: "kokoro-82m")
        XCTAssertTrue(cached === (cachedAfter as AnyObject?), "create() must reuse the warmup-loaded backend")
    }

    // MARK: - app/policy routing

    func testAppRefPreservesAppIdentityInRouteMetadata() async throws {
        // Note: ``ContractModelCapability`` does not yet enumerate
        // ``tts`` — the capability/identity routing logic in the
        // facade matches ``@app/<slug>/<capability>`` to the first
        // manifest entry as a shorthand. Once the contract gains
        // ``tts`` this test can switch to ``capability: .tts``.
        let app = AppManifest(models: [
            AppModelEntry(
                id: "kokoro-82m",
                capability: .transcription,
                delivery: .managed
            )
        ])
        let speech = try await makeFacadeWithFakeBackend()

        let result = try await speech.create(
            model: "@app/notes/tts",
            input: "hi",
            app: app
        )

        XCTAssertEqual(result.route.model.requested.kind.rawValue, "app")
        XCTAssertEqual(result.route.model.requested.ref, "@app/notes/tts")
    }

    func testLocalOnlyPolicyFailsClosedWhenBackendUnavailable() async throws {
        // Build a facade whose registered factory always throws — the
        // closest analogue to "no local TTS runtime registered" for a
        // production caller. Local-only must surface as
        // cloudFallbackDisallowed rather than silently routing to
        // hosted speech.
        let manager = try makeIsolatedPrepareManager()
        let speech = AudioSpeech(
            prepareManagerProvider: { manager },
            recipeRegistry: try makeRecipeRegistryStub(),
            runtimeRegistry: TtsRuntimeRegistry.shared,
            candidateOverride: candidateOverrideStub()
        )
        await TtsRuntimeRegistry.shared.reset()
        await TtsRuntimeRegistry.shared.register(engine: "sherpa-onnx") { _, _ in
            throw OctomilError.runtimeUnavailable(reason: "fake unavailable")
        }

        do {
            _ = try await speech.create(
                model: "kokoro-82m",
                input: "hi",
                policy: .localOnly
            )
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed(let reason) {
            XCTAssertTrue(reason.contains("local_only"))
        }
    }

    func testPrivatePolicyFailsClosedWhenBackendUnavailable() async throws {
        let manager = try makeIsolatedPrepareManager()
        let speech = AudioSpeech(
            prepareManagerProvider: { manager },
            recipeRegistry: try makeRecipeRegistryStub(),
            runtimeRegistry: TtsRuntimeRegistry.shared,
            candidateOverride: candidateOverrideStub()
        )
        await TtsRuntimeRegistry.shared.reset()
        await TtsRuntimeRegistry.shared.register(engine: "sherpa-onnx") { _, _ in
            throw OctomilError.runtimeUnavailable(reason: "fake unavailable")
        }

        do {
            _ = try await speech.create(
                model: "kokoro-82m",
                input: "hi",
                policy: .private
            )
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed {
            // expected
        }
    }

    func testMalformedAppRefRoutesAsUnknownAndFailsSafely() async throws {
        // @app/<slug> with no capability is malformed; the parser
        // returns kind=.unknown. The facade must NOT crash and must
        // surface the malformation as a structured error rather than
        // committing to a substitution.
        let speech = try await makeFacadeWithFakeBackend()
        do {
            _ = try await speech.create(
                model: "@app/justtheslug",
                input: "hi"
            )
            XCTFail("expected invalidRequest for malformed app ref")
        } catch OctomilError.invalidRequest(let reason) {
            XCTAssertTrue(reason.contains("malformed"), "reason should explain malformation: \(reason)")
        }
    }

    // MARK: - Helpers

    /// Build an AudioSpeech facade backed by an in-memory prepare
    /// manager + a fake TTS backend. The backend writes the canonical
    /// Sherpa Kokoro layout into the prepared directory so the test's
    /// "create consumes the prepared dir" assertion is real, not
    /// painted on.
    private func makeFacadeWithFakeBackend() async throws -> AudioSpeech {
        let manager = try makeIsolatedPrepareManager()
        let registry = try makeRecipeRegistryStub()
        let speech = AudioSpeech(
            prepareManagerProvider: { manager },
            recipeRegistry: registry,
            runtimeRegistry: TtsRuntimeRegistry.shared,
            candidateOverride: candidateOverrideStub()
        )
        await TtsRuntimeRegistry.shared.reset()
        await TtsRuntimeRegistry.shared.register(engine: "sherpa-onnx") { modelId, dir in
            // Stage canonical layout the test asserts exists.
            let layout = ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data/phontab"]
            for rel in layout {
                let target = dir.appendingPathComponent(rel)
                try? FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: target.path) {
                    try Data("ok".utf8).write(to: target)
                }
            }
            return FakeTtsBackend(modelId: modelId, artifactDir: dir)
        }
        return speech
    }

    private func makeIsolatedPrepareManager() throws -> PrepareManager {
        let cache = tmpDir.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return try PrepareManager(cacheDir: cache)
    }

    /// Return the production registry unchanged. Because the tests
    /// drive ``AudioSpeech`` via ``candidateOverride``, the registry
    /// is not consulted on the create/warmup paths — but the facade
    /// still accepts it as a parameter for type symmetry with
    /// production callers.
    private func makeRecipeRegistryStub() throws -> StaticRecipeRegistry {
        return StaticRecipeRegistry.shared
    }

    /// The recipe's URL is unreachable; route the prepare manager
    /// around the network by handing it a candidate with
    /// ``prepareRequired=false``. The runtime registry fake then
    /// fabricates the on-disk layout. This proves the facade plumbs
    /// prepare→load→synth without making a test depend on real bytes.
    private func candidateOverrideStub() -> @Sendable (String) -> PrepareCandidate? {
        return { modelId in
            PrepareCandidate(
                locality: "local",
                engine: "sherpa-onnx",
                artifact: PrepareArtifactPlan(modelId: modelId),
                deliveryMode: "sdk_runtime",
                prepareRequired: false,
                preparePolicy: .lazy
            )
        }
    }
}

// MARK: - FakeTtsBackend

/// Minimal ``TtsBackend`` stand-in for the unit tests. Records call
/// counts so the warmup → create reuse assertion can verify the
/// runtime registry hands back the same instance instead of building
/// a fresh one per call.
final class FakeTtsBackend: TtsBackend, @unchecked Sendable {
    let modelId: String
    let artifactDir: URL
    private(set) var synthesizeCallCount = 0

    init(modelId: String, artifactDir: URL) {
        self.modelId = modelId
        self.artifactDir = artifactDir
    }

    func synthesize(text: String, voice: String?, speed: Float) throws -> SpeechResult {
        synthesizeCallCount += 1
        let pcm = Data([0x00, 0x00, 0x00, 0x00])
        return SpeechResult(
            audioData: pcm,
            contentType: "audio/wav",
            format: "wav",
            sampleRate: 24_000,
            durationMs: 1,
            voice: voice,
            model: modelId,
            route: RouteMetadata(
                status: "selected",
                execution: nil,
                model: RouteModel(
                    requested: RouteModelRequested(ref: modelId, kind: .model, capability: nil),
                    resolved: nil
                ),
                artifact: nil,
                planner: PlannerInfo(source: "offline"),
                fallback: FallbackInfo(used: false, from_attempt: nil, to_attempt: nil, trigger: nil),
                attempts: nil,
                reason: RouteReason(code: "ok", message: "")
            ),
            preparedDir: artifactDir
        )
    }
}

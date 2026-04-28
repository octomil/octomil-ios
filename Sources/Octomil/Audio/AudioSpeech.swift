import Foundation

// MARK: - TTS Synthesis Result

/// Result of an on-device or cloud-routed `audio.speech.create(...)` call.
///
/// Mirrors the shape of ``HostedSpeechResponse`` for the local/sdk_runtime
/// path so callers can program against a single response surface
/// regardless of locality.
public struct SpeechResult: Sendable {
    public let audioData: Data
    public let contentType: String
    public let format: String
    public let sampleRate: Int
    public let durationMs: Int
    public let voice: String?
    public let model: String
    /// Canonical route metadata attached by the speech facade so
    /// callers can read ``locality``/``mode``/``engine`` without
    /// reaching into private types.
    public let route: RouteMetadata
    /// The on-disk artifact directory the synthesizing backend
    /// consumed for this call. ``nil`` for cloud/hosted paths.
    public let preparedDir: URL?

    public init(
        audioData: Data,
        contentType: String,
        format: String,
        sampleRate: Int,
        durationMs: Int,
        voice: String?,
        model: String,
        route: RouteMetadata,
        preparedDir: URL? = nil
    ) {
        self.audioData = audioData
        self.contentType = contentType
        self.format = format
        self.sampleRate = sampleRate
        self.durationMs = durationMs
        self.voice = voice
        self.model = model
        self.route = route
        self.preparedDir = preparedDir
    }
}

// MARK: - TtsBackend

/// Engine-agnostic on-device TTS surface. ``OctomilRuntimeSherpaTTS``
/// adapts ``SherpaTtsEngine`` to this protocol; tests register a
/// fake implementation to drive the facade end-to-end without
/// linking sherpa-onnx.
public protocol TtsBackend: AnyObject, Sendable {
    var modelId: String { get }
    /// Synthesize ``text``; ``voice`` and ``speed`` are passed through to the engine.
    func synthesize(text: String, voice: String?, speed: Float) throws -> SpeechResult
}

/// Factory used by ``TtsRuntimeRegistry`` when ``warmup``/``create``
/// needs to materialize a backend on top of a prepared artifact dir.
public typealias TtsBackendFactory = @Sendable (_ modelId: String, _ artifactDir: URL) throws -> TtsBackend

// MARK: - TtsRuntimeRegistry

/// Process-wide registry of TTS backend factories keyed by engine
/// name (e.g. ``"sherpa-onnx"``). Mirrors the engine-name keying used
/// by ``EngineRegistry`` for ASR. Held as a single shared actor so
/// concurrent ``client.warmup(...)``/``audio.speech.create(...)`` calls
/// see a coherent view of the loaded-backend cache.
public actor TtsRuntimeRegistry {
    public static let shared = TtsRuntimeRegistry()

    private var factories: [String: TtsBackendFactory] = [:]
    /// Cached loaded backends keyed by ``modelId``. ``warmup`` populates
    /// this; ``create`` reuses a hit, otherwise loads on demand.
    private var loaded: [String: TtsBackend] = [:]

    public init() {}

    /// Register a factory that produces a ``TtsBackend`` from a
    /// prepared artifact directory.
    public func register(engine: String, factory: @escaping TtsBackendFactory) {
        factories[engine] = factory
    }

    /// Remove a registration; primarily useful in tests.
    public func unregister(engine: String) {
        factories.removeValue(forKey: engine)
    }

    public func factory(for engine: String) -> TtsBackendFactory? {
        factories[engine]
    }

    /// Load (or reuse) a backend for ``modelId``, building it from
    /// ``artifactDir`` via the registered factory for ``engine``.
    public func loadOrReuse(
        engine: String,
        modelId: String,
        artifactDir: URL
    ) throws -> TtsBackend {
        if let cached = loaded[modelId] { return cached }
        guard let factory = factories[engine] else {
            throw OctomilError.runtimeUnavailable(
                reason: "No TTS runtime registered for engine '\(engine)'. " +
                    "Add `import OctomilRuntimeSherpaTTS` and call " +
                    "`SherpaTtsRuntime.register()` (iOS), or register a custom backend " +
                    "via `TtsRuntimeRegistry.shared.register(engine:factory:)`."
            )
        }
        let backend = try factory(modelId, artifactDir)
        loaded[modelId] = backend
        return backend
    }

    /// Cache lookup. Used by tests to assert the warmup→create reuse
    /// path; callers normally go through ``loadOrReuse``.
    public func cached(modelId: String) -> TtsBackend? { loaded[modelId] }

    /// Drop the cache; primarily useful in tests.
    public func reset() {
        loaded.removeAll()
        factories.removeAll()
    }
}

// MARK: - AudioSpeech

/// Public ``audio.speech`` namespace: ``client.audio.speech.create(...)``
/// and ``client.audio.speech.warmup(...)``.
///
/// This facade is the single public surface for batch text-to-speech
/// synthesis on iOS. It enforces routing policy + app identity, drives
/// the prepare lifecycle through ``PrepareManager``, and consumes the
/// loaded backend from ``TtsRuntimeRegistry``.
///
/// Streaming TTS is intentionally not exposed — the contract treats
/// streaming as ``not_applicable`` until a real sample-streaming
/// surface ships.
public final class AudioSpeech: @unchecked Sendable {

    private let prepareManagerProvider: @Sendable () throws -> PrepareManager
    private let recipeRegistry: StaticRecipeRegistry
    private let runtimeRegistry: TtsRuntimeRegistry
    /// Test seam: lets the unit test drive ``create`` with a candidate
    /// it constructed directly, bypassing the planner. Production
    /// callers leave this nil and the facade derives a candidate from
    /// the static recipe registry.
    private let candidateOverride: (@Sendable (_ modelId: String) -> PrepareCandidate?)?

    public init(
        prepareManagerProvider: @escaping @Sendable () throws -> PrepareManager = {
            try PrepareManager()
        },
        recipeRegistry: StaticRecipeRegistry = .shared,
        runtimeRegistry: TtsRuntimeRegistry = .shared,
        candidateOverride: (@Sendable (_ modelId: String) -> PrepareCandidate?)? = nil
    ) {
        self.prepareManagerProvider = prepareManagerProvider
        self.recipeRegistry = recipeRegistry
        self.runtimeRegistry = runtimeRegistry
        self.candidateOverride = candidateOverride
    }

    // MARK: - create

    /// Synthesize speech from text and return WAV/PCM bytes plus
    /// route metadata.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. ``"kokoro-82m"``) or canonical
    ///     reference (``"@app/<slug>/tts"``). ``@app/...`` references
    ///     preserve the app identity end-to-end through route metadata.
    ///   - input: Text to synthesize. Must be non-empty.
    ///   - voice: Optional voice id/name (engine-specific).
    ///   - speed: Speech rate multiplier (default 1.0).
    ///   - policy: Routing policy. ``.localOnly``/``.private`` never
    ///     fall back to cloud — if the local backend is unavailable
    ///     the call throws ``OctomilError.cloudFallbackDisallowed``.
    ///   - app: Optional ``AppManifest`` whose effective routing policy
    ///     is used when ``policy`` is ``nil``.
    public func create(
        model: String,
        input: String,
        voice: String? = nil,
        speed: Float = 1.0,
        policy: AppRoutingPolicy? = nil,
        app: AppManifest? = nil
    ) async throws -> SpeechResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OctomilError.invalidInput(reason: "`input` must be a non-empty string.")
        }

        let parsed = ParsedModelRef.parse(model)
        if parsed.kind == .unknown {
            throw OctomilError.invalidRequest(
                reason: "Model reference '\(model)' is malformed. " +
                    "Expected a model id, '@app/<slug>/<capability>', or '@capability/<cap>'."
            )
        }
        let resolvedPolicy = Self.resolvePolicy(
            explicit: policy,
            app: app,
            parsed: parsed
        )

        // App identity must travel through to route metadata. For
        // @app/<slug>/<capability> refs the appSlug is part of the
        // canonical identity; for plain refs the app manifest's
        // first matching entry stamps it.
        let appSlug = parsed.appSlug ?? Self.appSlug(for: parsed.modelSlug ?? model, in: app)

        let candidate = try buildCandidate(modelId: parsed.modelSlug ?? model, parsed: parsed, app: app)
        let outcome = try await prepareManagerProvider().prepare(candidate, mode: .lazy)

        let engine = candidate.engine ?? "sherpa-onnx"
        let backend: TtsBackend
        do {
            backend = try await runtimeRegistry.loadOrReuse(
                engine: engine,
                modelId: outcome.artifactId,
                artifactDir: outcome.artifactDir
            )
        } catch {
            // Routing policy gates: local-only/private MUST fail
            // closed when the local backend is unavailable. Other
            // policies surface the underlying runtimeUnavailable
            // because the iOS SDK does not yet wire the hosted-TTS
            // gateway into ``audio.speech.create`` (the @hosted client
            // has its own surface).
            if Self.deniesCloudFallback(resolvedPolicy) {
                throw OctomilError.cloudFallbackDisallowed(
                    reason: "TTS routing policy '\(resolvedPolicy?.rawValue ?? "local_only")' " +
                        "forbids cloud fallback and the local backend is unavailable: \(error.localizedDescription)"
                )
            }
            throw error
        }

        let synth = try backend.synthesize(text: input, voice: voice, speed: speed)

        let route = RouteMetadata(
            status: "selected",
            execution: RouteExecution(
                locality: "local",
                mode: "sdk_runtime",
                engine: engine
            ),
            model: RouteModel(
                requested: RouteModelRequested(
                    ref: parsed.raw,
                    kind: parsed.kind.rawValue,
                    capability: "tts"
                ),
                resolved: RouteModelResolved(
                    id: outcome.artifactId,
                    slug: appSlug
                )
            ),
            artifact: RouteArtifact(
                cache: ArtifactCache(status: outcome.cached ? "hit" : "miss")
            ),
            planner: PlannerInfo(source: parsed.kind == .app ? "cache" : "offline"),
            fallback: FallbackInfo(used: false),
            reason: RouteReason(code: "ok", message: resolvedPolicy?.rawValue ?? "")
        )

        return SpeechResult(
            audioData: synth.audioData,
            contentType: synth.contentType,
            format: synth.format,
            sampleRate: synth.sampleRate,
            durationMs: synth.durationMs,
            voice: synth.voice ?? voice,
            model: synth.model,
            route: route,
            preparedDir: outcome.artifactDir
        )
    }

    // MARK: - warmup

    /// Prepare the artifact, load the backend, and cache it for the
    /// next ``create`` call.
    ///
    /// Mirrors Python's ``client.warmup(model=, capability="tts")``: a
    /// successful warmup guarantees the next ``create`` will hit the
    /// cached backend instead of re-loading.
    @discardableResult
    public func warmup(
        model: String,
        app: AppManifest? = nil
    ) async throws -> WarmupOutcome {
        let parsed = ParsedModelRef.parse(model)
        let candidate = try buildCandidate(modelId: parsed.modelSlug ?? model, parsed: parsed, app: app)
        let outcome = try await prepareManagerProvider().prepare(candidate, mode: .explicit)
        let engine = candidate.engine ?? "sherpa-onnx"
        _ = try await runtimeRegistry.loadOrReuse(
            engine: engine,
            modelId: outcome.artifactId,
            artifactDir: outcome.artifactDir
        )
        return WarmupOutcome(
            modelId: outcome.artifactId,
            engine: engine,
            artifactDir: outcome.artifactDir,
            cached: outcome.cached
        )
    }

    // MARK: - Helpers

    private func buildCandidate(
        modelId: String,
        parsed: ParsedModelRef,
        app: AppManifest?
    ) throws -> PrepareCandidate {
        if let override = candidateOverride?(modelId) {
            return override
        }
        let recipeId = Self.recipeId(modelId: modelId, parsed: parsed, app: app)
        guard recipeRegistry.recipe(for: recipeId) != nil else {
            throw OctomilError.modelNotFound(modelId: recipeId)
        }
        return PrepareCandidate(
            locality: "local",
            engine: "sherpa-onnx",
            artifact: PrepareArtifactPlan(
                modelId: modelId,
                source: "static_recipe",
                recipeId: recipeId
            ),
            deliveryMode: "sdk_runtime",
            prepareRequired: true,
            preparePolicy: .lazy
        )
    }

    private static func recipeId(
        modelId: String,
        parsed: ParsedModelRef,
        app: AppManifest?
    ) -> String {
        if parsed.kind == .app, let app {
            // Prefer an entry whose capability matches the parsed
            // capability when the contract enum knows about it (e.g.
            // ``transcription``). For capabilities the contract does
            // NOT yet model (e.g. ``tts``) we fall back to the first
            // entry in the manifest — the same shorthand the Python
            // SDK uses for single-model app manifests.
            if let cap = parsed.capability,
               let entry = app.models.first(where: { $0.capability.rawValue == cap }) {
                return entry.id
            }
            if let first = app.models.first {
                return first.id
            }
        }
        return modelId
    }

    private static func resolvePolicy(
        explicit: AppRoutingPolicy?,
        app: AppManifest?,
        parsed: ParsedModelRef
    ) -> AppRoutingPolicy? {
        if let explicit { return explicit }
        guard let app else { return nil }
        if parsed.kind == .app {
            if let cap = parsed.capability,
               let entry = app.models.first(where: { $0.capability.rawValue == cap }) {
                return entry.effectiveRoutingPolicy
            }
            if let first = app.models.first {
                return first.effectiveRoutingPolicy
            }
        }
        if let entry = app.models.first(where: { $0.id == (parsed.modelSlug ?? parsed.raw) }) {
            return entry.effectiveRoutingPolicy
        }
        return nil
    }

    private static func appSlug(for modelId: String, in app: AppManifest?) -> String? {
        guard let app else { return nil }
        return app.models.first(where: { $0.id == modelId })?.id
    }

    public static func deniesCloudFallback(_ policy: AppRoutingPolicy?) -> Bool {
        guard let policy else { return false }
        switch policy {
        case .localOnly, .private: return true
        default: return false
        }
    }

    /// Shared policy resolver for ``AudioTranscriptions.create`` — same
    /// rules as TTS so the two audio surfaces enforce identity and
    /// fail-closed routing the same way.
    public static func resolvePolicyForTranscription(
        explicit: AppRoutingPolicy?,
        app: AppManifest?,
        parsed: ParsedModelRef
    ) -> AppRoutingPolicy? {
        return resolvePolicy(explicit: explicit, app: app, parsed: parsed)
    }
}

// MARK: - Warmup outcome

public struct WarmupOutcome: Sendable {
    public let modelId: String
    public let engine: String
    public let artifactDir: URL
    public let cached: Bool

    public init(modelId: String, engine: String, artifactDir: URL, cached: Bool) {
        self.modelId = modelId
        self.engine = engine
        self.artifactDir = artifactDir
        self.cached = cached
    }
}


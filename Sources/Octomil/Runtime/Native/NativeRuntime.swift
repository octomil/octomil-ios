// Swift mirror of the octomil-runtime C ABI surface.
//
// Both the in-process stub (Sprint 1, Approach A) and the real FFI
// binding (Sprint 2, Approach B) conform to these protocols. The
// surface follows `octomil-runtime/include/octomil/runtime.h` and the
// matching native loader cdef; changes here require a matched runtime
// contract update first.
//
// Spec: docs/specs/2026-05-06-ios-stub-runtime.md

import Foundation

// MARK: - ABI version

/// Pinned ABI version this binding targets. The FFI path performs a
/// handshake at load (pin major exact, minor ≥ required) and fails fast
/// with `.versionMismatch` on drift; the stub ignores this but keeps it
/// here to document intent for Approach B.
///
/// IMPORTANT: ``requiredMinor`` stays at 10 even though the binding
/// declares optional ABI-11 image symbols (`oct_session_send_image`
/// etc.). Image-input callers enforce ``imageInputMinimumMinor`` (11)
/// inline so that existing ABI-10 capabilities continue to work
/// against an older runtime; only the image path requires the higher
/// floor. The image symbols are looked up via dlsym lazily and may be
/// absent on minor-10 runtimes — that absence surfaces as
/// ``NativeRuntimeError(status: .unsupported)`` at the point of call
/// rather than at runtime open. See octomil-runtime PR #86 (1d92e35).
public enum NativeABI {
    public static let requiredMajor: UInt32 = 0
    public static let requiredMinor: UInt32 = 10
    /// Minimum runtime ABI minor that exposes the image-input surface
    /// (``oct_session_send_image`` + ``oct_image_view_t``). Enforced as
    /// an inner gate inside the image-send path; runtime-open is NOT
    /// gated by this.
    public static let imageInputMinimumMinor: UInt32 = 11
}

// MARK: - Status (oct_status_t — runtime.h:161-169)

public enum NativeStatus: UInt32, Sendable {
    case ok = 0
    case invalidInput = 1
    case unsupported = 2
    case notFound = 3
    case busy = 4
    case timeout = 5
    case cancelled = 6
    case internalError = 7
    case versionMismatch = 8
}

public struct NativeRuntimeError: Error, Sendable {
    public let status: NativeStatus
    public let message: String?

    public init(status: NativeStatus, message: String? = nil) {
        self.status = status
        self.message = message
    }

    public var sdkErrorCode: ErrorCode? {
        status.nativeBridgeErrorCode
    }
}

extension NativeStatus {
    /// Default status-to-SDK-code mapping for the native bridge layer.
    /// Capability-specific surfaces may refine `.unsupported` when they
    /// have enough context; runtime open/capability discovery treats it
    /// as `runtime_unavailable`.
    public var nativeBridgeErrorCode: ErrorCode? {
        switch self {
        case .ok:
            return nil
        case .invalidInput:
            return .invalidInput
        case .unsupported, .busy, .versionMismatch:
            return .runtimeUnavailable
        case .notFound:
            return .modelNotFound
        case .timeout:
            return .streamInterrupted
        case .cancelled:
            return .cancelled
        case .internalError:
            return .inferenceFailed
        }
    }
}

// MARK: - Priority (oct_priority_t — runtime.h:503-505)

public enum NativePriority: UInt32, Sendable {
    case speculative = 0
    case prefetch = 1
    case foreground = 2
}

// MARK: - Capabilities (oct_capabilities_t — loader.py:371-383)

/// Host-runtime introspection: RAM, accelerators, supported engines.
/// Distinct from the SDK-level `RuntimeCapabilities` in `Runtime/Core/`,
/// which describes per-model capabilities (tool calls, streaming).
public struct NativeCapabilities: Sendable {
    public let supportedEngines: [String]
    public let supportedCapabilities: [String]
    public let supportedArchs: [String]
    public let ramTotalBytes: UInt64
    public let ramAvailableBytes: UInt64
    public let hasAppleSilicon: Bool
    public let hasCUDA: Bool
    public let hasMetal: Bool

    public init(
        supportedEngines: [String] = [],
        supportedCapabilities: [String] = [],
        supportedArchs: [String] = [],
        ramTotalBytes: UInt64 = 0,
        ramAvailableBytes: UInt64 = 0,
        hasAppleSilicon: Bool = false,
        hasCUDA: Bool = false,
        hasMetal: Bool = false
    ) {
        self.supportedEngines = supportedEngines
        self.supportedCapabilities = supportedCapabilities
        self.supportedArchs = supportedArchs
        self.ramTotalBytes = ramTotalBytes
        self.ramAvailableBytes = ramAvailableBytes
        self.hasAppleSilicon = hasAppleSilicon
        self.hasCUDA = hasCUDA
        self.hasMetal = hasMetal
    }
}

// MARK: - Operational envelope (loader.py:502-513)

/// Appended verbatim to every event by the runtime — never minted.
/// Echoed from the session config that opened the originating session.
public struct NativeOperationalEnvelope: Sendable {
    public let requestID: String
    public let routeID: String
    public let traceID: String
    public let engineVersion: String
    public let adapterVersion: String
    public let accelerator: String
    public let artifactDigest: String
    public let cacheWasHit: Bool

    public init(
        requestID: String = "",
        routeID: String = "",
        traceID: String = "",
        engineVersion: String = "",
        adapterVersion: String = "",
        accelerator: String = "",
        artifactDigest: String = "",
        cacheWasHit: Bool = false
    ) {
        self.requestID = requestID
        self.routeID = routeID
        self.traceID = traceID
        self.engineVersion = engineVersion
        self.adapterVersion = adapterVersion
        self.accelerator = accelerator
        self.artifactDigest = artifactDigest
        self.cacheWasHit = cacheWasHit
    }
}

// MARK: - Sample format (runtime.h:831-832)

public enum NativeSampleFormat: UInt32, Sendable {
    case pcmS16LE = 1
    case pcmF32LE = 2
}

// MARK: - Image input (oct_image_view_t / OCT_IMAGE_MIME_* — runtime.h ABI minor 11)
//
// Optional ABI-11 surface. Symbol presence is gated by the runtime's
// reported minor (>= 11); the binding's required minor stays at 10
// (see ``NativeABI``). The capability `embeddings.image` is
// BLOCKED_WITH_PROOF at this commit — the runtime advertises the
// symbol but `oct_session_send_image` returns OCT_STATUS_UNSUPPORTED
// unconditionally until the adapter PR lands and removes the
// capability from the blocked set. Surfaced here so SDK callers can
// cdef against the shape without flipping the required floor.

/// MIME discriminator for ``NativeImageView``. Closed enum with a
/// `unknown` sentinel matching the C-side `OCT_IMAGE_MIME_UNKNOWN`
/// forward-compat slot — bindings that observe an unknown raw value
/// SHOULD treat it as `unknown` and surface `INVALID_INPUT` instead
/// of crashing.
public enum NativeImageMime: UInt32, Sendable {
    /// Future-compat sentinel; never set by callers. Reserved for
    /// runtime-side enum extension. (matches `OCT_IMAGE_MIME_UNKNOWN`).
    case unknown = 0
    /// `image/png` — encoded byte buffer.
    case png = 1
    /// `image/jpeg` — encoded byte buffer.
    case jpeg = 2
    /// `image/webp` — encoded byte buffer.
    case webp = 3
    /// Raw decoded uint8 RGB pixel buffer (`width * height * 3`).
    case rgb8 = 4
}

/// Swift-friendly mirror of `oct_image_view_t`. Callers pass an
/// encoded (PNG/JPEG/WEBP) or raw (`rgb8`) byte buffer; the runtime
/// copies internally if it needs to retain. Lifetime is the duration
/// of the ``NativeSession/sendImage(_:mime:)`` call.
public struct NativeImageView: Sendable {
    /// Encoded image bytes (PNG/JPEG/WEBP) or raw decoded RGB8 pixel
    /// buffer. Empty data is rejected as INVALID_INPUT by the runtime.
    public let bytes: Data
    /// Content-type discriminator. Unknown values reject as
    /// INVALID_INPUT before reaching the runtime.
    public let mime: NativeImageMime

    public init(bytes: Data, mime: NativeImageMime) {
        self.bytes = bytes
        self.mime = mime
    }
}

// MARK: - Event payloads (subset of the oct_event union)
//
// Only payloads the stub fires are modelled. Runtime-scope events
// (cache, queued, preempted, memory_pressure, thermal_state,
// watchdog_timeout, model_evicted, metric, input_dropped) are
// intentionally omitted; add cases when Approach B fires them.

public struct NativeAudioChunkPayload: Sendable {
    public let pcm: Data
    public let sampleRate: UInt32
    public let sampleFormat: NativeSampleFormat
    public let channels: UInt16
    public let isFinal: Bool

    public init(
        pcm: Data,
        sampleRate: UInt32,
        sampleFormat: NativeSampleFormat,
        channels: UInt16,
        isFinal: Bool
    ) {
        self.pcm = pcm
        self.sampleRate = sampleRate
        self.sampleFormat = sampleFormat
        self.channels = channels
        self.isFinal = isFinal
    }
}

public struct NativeEmbeddingVectorPayload: Sendable {
    public let values: [Float]
    public let dimension: UInt32
    public let inputTokens: UInt32
    public let index: UInt32
    public let poolingType: UInt32
    public let isNormalized: Bool

    public init(
        values: [Float],
        dimension: UInt32,
        inputTokens: UInt32,
        index: UInt32,
        poolingType: UInt32,
        isNormalized: Bool
    ) {
        self.values = values
        self.dimension = dimension
        self.inputTokens = inputTokens
        self.index = index
        self.poolingType = poolingType
        self.isNormalized = isNormalized
    }
}

public struct NativeTranscriptChunkPayload: Sendable {
    public let utf8: String

    public init(utf8: String) {
        self.utf8 = utf8
    }
}

public struct NativeTranscriptSegmentPayload: Sendable {
    public let utf8: String
    public let nBytes: UInt32
    public let startMs: UInt32
    public let endMs: UInt32
    public let segmentIndex: UInt32
    public let isFinal: Bool

    public init(
        utf8: String,
        nBytes: UInt32,
        startMs: UInt32,
        endMs: UInt32,
        segmentIndex: UInt32,
        isFinal: Bool
    ) {
        self.utf8 = utf8
        self.nBytes = nBytes
        self.startMs = startMs
        self.endMs = endMs
        self.segmentIndex = segmentIndex
        self.isFinal = isFinal
    }
}

public struct NativeTranscriptFinalPayload: Sendable {
    public let utf8: String
    public let nBytes: UInt32
    public let nSegments: UInt32
    public let durationMs: UInt32

    public init(utf8: String, nBytes: UInt32, nSegments: UInt32, durationMs: UInt32) {
        self.utf8 = utf8
        self.nBytes = nBytes
        self.nSegments = nSegments
        self.durationMs = durationMs
    }
}

public struct NativeErrorPayload: Sendable {
    public let code: String
    public let message: String
    public let errorCode: UInt32

    public init(code: String, message: String, errorCode: UInt32) {
        self.code = code
        self.message = message
        self.errorCode = errorCode
    }
}

public struct NativeVADTransitionPayload: Sendable {
    public let transitionKind: UInt32
    public let timestampMs: UInt32
    public let confidence: Float

    public init(transitionKind: UInt32, timestampMs: UInt32, confidence: Float) {
        self.transitionKind = transitionKind
        self.timestampMs = timestampMs
        self.confidence = confidence
    }
}

public struct NativeDiarizationSegmentPayload: Sendable {
    public let startMs: UInt32
    public let endMs: UInt32
    public let speakerID: UInt16
    public let speakerLabel: String

    public init(startMs: UInt32, endMs: UInt32, speakerID: UInt16, speakerLabel: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.speakerID = speakerID
        self.speakerLabel = speakerLabel
    }
}

public struct NativeCachePayload: Sendable {
    public let layer: String
    public let savedTokens: UInt32

    public init(layer: String, savedTokens: UInt32) {
        self.layer = layer
        self.savedTokens = savedTokens
    }
}

public struct NativeSessionStartedPayload: Sendable {
    public let engine: String
    public let modelDigest: String
    public let locality: String
    public let streamingMode: String
    public let runtimeBuildTag: String

    public init(engine: String, modelDigest: String, locality: String, streamingMode: String, runtimeBuildTag: String) {
        self.engine = engine
        self.modelDigest = modelDigest
        self.locality = locality
        self.streamingMode = streamingMode
        self.runtimeBuildTag = runtimeBuildTag
    }
}

public struct NativeSessionCompletedPayload: Sendable {
    public let setupMs: Float
    public let engineFirstChunkMs: Float
    public let e2eFirstChunkMs: Float
    public let totalLatencyMs: Float
    public let queuedMs: Float
    public let observedChunks: UInt32
    public let capabilityVerified: Bool
    public let terminalStatus: NativeStatus

    public init(
        setupMs: Float,
        engineFirstChunkMs: Float,
        e2eFirstChunkMs: Float,
        totalLatencyMs: Float,
        queuedMs: Float,
        observedChunks: UInt32,
        capabilityVerified: Bool,
        terminalStatus: NativeStatus
    ) {
        self.setupMs = setupMs
        self.engineFirstChunkMs = engineFirstChunkMs
        self.e2eFirstChunkMs = e2eFirstChunkMs
        self.totalLatencyMs = totalLatencyMs
        self.queuedMs = queuedMs
        self.observedChunks = observedChunks
        self.capabilityVerified = capabilityVerified
        self.terminalStatus = terminalStatus
    }
}

public struct NativeModelLoadedPayload: Sendable {
    public let engine: String
    public let modelID: String
    public let artifactDigest: String
    public let loadMs: UInt64
    public let warmMs: UInt64
    public let policyPreset: String
    public let source: String

    public init(
        engine: String,
        modelID: String,
        artifactDigest: String,
        loadMs: UInt64,
        warmMs: UInt64,
        policyPreset: String,
        source: String
    ) {
        self.engine = engine
        self.modelID = modelID
        self.artifactDigest = artifactDigest
        self.loadMs = loadMs
        self.warmMs = warmMs
        self.policyPreset = policyPreset
        self.source = source
    }
}

// MARK: - Event (oct_event_t — loader.py:389-514)

public enum NativeEvent: Sendable {
    case sessionStarted(NativeSessionStartedPayload, envelope: NativeOperationalEnvelope)
    case audioChunk(NativeAudioChunkPayload, envelope: NativeOperationalEnvelope)
    case transcriptChunk(NativeTranscriptChunkPayload, envelope: NativeOperationalEnvelope)
    case transcriptSegment(NativeTranscriptSegmentPayload, envelope: NativeOperationalEnvelope)
    case transcriptFinal(NativeTranscriptFinalPayload, envelope: NativeOperationalEnvelope)
    case embeddingVector(NativeEmbeddingVectorPayload, envelope: NativeOperationalEnvelope)
    case vadTransition(NativeVADTransitionPayload, envelope: NativeOperationalEnvelope)
    case diarizationSegment(NativeDiarizationSegmentPayload, envelope: NativeOperationalEnvelope)
    case ttsAudioChunk(NativeAudioChunkPayload, envelope: NativeOperationalEnvelope)
    case cacheHit(NativeCachePayload, envelope: NativeOperationalEnvelope)
    case cacheMiss(NativeCachePayload, envelope: NativeOperationalEnvelope)
    case turnEnded(envelope: NativeOperationalEnvelope)
    case error(NativeErrorPayload, envelope: NativeOperationalEnvelope)
    case sessionCompleted(NativeSessionCompletedPayload, envelope: NativeOperationalEnvelope)
    case modelLoaded(NativeModelLoadedPayload, envelope: NativeOperationalEnvelope)

    public var envelope: NativeOperationalEnvelope {
        switch self {
        case .sessionStarted(_, let env),
             .audioChunk(_, let env),
             .transcriptChunk(_, let env),
             .transcriptSegment(_, let env),
             .transcriptFinal(_, let env),
             .embeddingVector(_, let env),
             .vadTransition(_, let env),
             .diarizationSegment(_, let env),
             .ttsAudioChunk(_, let env),
             .cacheHit(_, let env),
             .cacheMiss(_, let env),
             .error(_, let env),
             .sessionCompleted(_, let env),
             .modelLoaded(_, let env):
            return env
        case .turnEnded(let env):
            return env
        }
    }
}

// MARK: - Config types

public struct NativeRuntimeConfig: Sendable {
    public let artifactRoot: String
    public let maxSessions: UInt32

    public init(artifactRoot: String, maxSessions: UInt32 = 16) {
        self.artifactRoot = artifactRoot
        self.maxSessions = maxSessions
    }
}

public struct NativeModelConfig: Sendable {
    public let modelURI: String
    public let artifactDigest: String
    public let engineHint: String?
    public let policyPreset: String?
    public let acceleratorPref: UInt32
    public let ramBudgetBytes: UInt64

    public init(
        modelURI: String,
        artifactDigest: String,
        engineHint: String? = nil,
        policyPreset: String? = nil,
        acceleratorPref: UInt32 = 0,
        ramBudgetBytes: UInt64 = 0
    ) {
        self.modelURI = modelURI
        self.artifactDigest = artifactDigest
        self.engineHint = engineHint
        self.policyPreset = policyPreset
        self.acceleratorPref = acceleratorPref
        self.ramBudgetBytes = ramBudgetBytes
    }
}

/// v=3 session config (loader.py:518-549). The runtime requires a
/// non-nil `model` handle on `openSession`; the model is passed
/// alongside the config rather than embedded so the binding owns the
/// lifetime story (Swift keeps the model retained for the session's
/// lifetime via the `openSession` parameter).
public struct NativeSessionConfig: Sendable {
    public let modelURI: String
    public let capability: String
    public let locality: String
    public let policyPreset: String?
    public let speakerID: String?
    public let sampleRateIn: UInt32
    public let sampleRateOut: UInt32
    public let priority: NativePriority
    public let requestID: String?
    public let routeID: String?
    public let traceID: String?
    public let kvPrefixKey: String?

    public init(
        modelURI: String,
        capability: String,
        locality: String = "on-device",
        policyPreset: String? = nil,
        speakerID: String? = nil,
        sampleRateIn: UInt32 = 16000,
        sampleRateOut: UInt32 = 24000,
        priority: NativePriority = .foreground,
        requestID: String? = nil,
        routeID: String? = nil,
        traceID: String? = nil,
        kvPrefixKey: String? = nil
    ) {
        self.modelURI = modelURI
        self.capability = capability
        self.locality = locality
        self.policyPreset = policyPreset
        self.speakerID = speakerID
        self.sampleRateIn = sampleRateIn
        self.sampleRateOut = sampleRateOut
        self.priority = priority
        self.requestID = requestID
        self.routeID = routeID
        self.traceID = traceID
        self.kvPrefixKey = kvPrefixKey
    }
}

// MARK: - Telemetry sink

/// Sendable so the FFI path can hand it to a `@convention(c)` trampoline
/// without a retroactive Sendable bolt-on.
public typealias NativeTelemetrySink = @Sendable (NativeEvent) -> Void

// MARK: - Protocols
//
// Cascade close order: sessions → models → runtime. Implementations
// MUST encode this in actor logic; comments alone are not load-bearing.
//
// Pre-invalidation rule: when a parent handle closes, child wrappers
// must mark themselves invalid before the parent C-side close runs, so
// finalizers cannot dereference freed handles. The stub enforces this
// via Swift retain semantics; Approach B will add an explicit invalid
// flag.

public protocol NativeRuntime: Actor {
    static func open(
        config: NativeRuntimeConfig,
        telemetrySink: NativeTelemetrySink?
    ) async throws -> Self

    func capabilities() async throws -> NativeCapabilities

    func openModel(config: NativeModelConfig) async throws -> any NativeModel

    /// v=3 session open. The runtime returns INVALID_INPUT if `model` is
    /// nil; the binding MUST keep `model` alive until the returned
    /// session has been closed.
    func openSession(
        config: NativeSessionConfig,
        model: any NativeModel
    ) async throws -> any NativeSession

    /// Model-free session open for capabilities that do not consume an
    /// ``oct_model_t`` (``audio.vad``, ``audio.diarization``). Passes
    /// ``model = NULL`` in ``oct_session_config_t``; the runtime adapter
    /// resolves the artifact from its own env-var path.
    ///
    /// Default implementation throws ``NativeRuntimeError(.unsupported)``
    /// so existing conformers remain backward-compatible. Override in
    /// ``FFINativeRuntime`` and ``StubRuntime`` to activate the path.
    func openSessionModelFree(config: NativeSessionConfig) async throws -> any NativeSession

    /// Precondition: all models opened via this runtime have been
    /// closed first. Violation triggers a precondition failure.
    func close() async
}

extension NativeRuntime {
    /// Fail-safe default: model-free sessions are unsupported unless the
    /// concrete conformer overrides this method.
    public func openSessionModelFree(config: NativeSessionConfig) async throws -> any NativeSession {
        throw NativeRuntimeError(
            status: .unsupported,
            message: "openSessionModelFree is not implemented for this NativeRuntime conformer"
        )
    }
}

public protocol NativeModel: Actor {
    func warm() async throws
    func evict() async throws

    /// Throws `NativeRuntimeError(.busy)` when sessions still borrow the
    /// model — handle remains valid; binding retries after closing
    /// sessions.
    func close() async throws
}

public protocol NativeSession: Actor {
    /// `pcm` is interleaved float32 LE (matches `oct_audio_view_t.samples` —
    /// input is always f32; output `audioChunk` events carry an explicit
    /// format).
    func sendAudio(_ pcm: Data, sampleRate: UInt32, channels: UInt16) async throws
    func sendText(_ utf8: String) async throws

    /// Optional ABI-11 image-input surface (matches
    /// `oct_session_send_image` introduced in octomil-runtime PR #86).
    ///
    /// Conformers SHOULD gate this on `runtimeAbiMinor >= 11` AND a
    /// capabilities probe that contains `embeddings.image`; otherwise
    /// throw ``NativeRuntimeError(status: .unsupported, message:
    /// "embeddings.image")``. The default implementation throws
    /// `.unsupported` so existing conformers (notably the in-process
    /// stub) remain backward-compatible.
    ///
    /// BLOCKED_WITH_PROOF at this commit — the runtime export is a
    /// stub that returns OCT_STATUS_UNSUPPORTED unconditionally until
    /// the embeddings.image adapter lands and removes the capability
    /// from the blocked set. No public SDK facade advertises image
    /// embeddings as live; calling this against a v0.1.10 (minor=10)
    /// runtime fails with `.unsupported` as a clean inner gate.
    func sendImage(_ view: NativeImageView) async throws

    /// Returns the next event. Returns nil on TIMEOUT (mirrors the C
    /// `OCT_STATUS_TIMEOUT` + `out->type = OCT_EVENT_NONE` convention).
    func pollEvent(timeout: TimeInterval) async throws -> NativeEvent?

    func cancel() async throws
    func close() async
}

extension NativeSession {
    /// Fail-safe default: image input is unsupported unless the
    /// concrete conformer overrides this method. Matches the
    /// ``NativeRuntime/openSessionModelFree(config:)`` extension
    /// pattern so existing conformers (Stub, hosted bridges) don't
    /// need to change.
    public func sendImage(_ view: NativeImageView) async throws {
        throw NativeRuntimeError(
            status: .unsupported,
            message: "embeddings.image is BLOCKED_WITH_PROOF: this NativeSession does not implement sendImage."
        )
    }
}

// Swift mirror of the octomil-runtime C ABI surface.
//
// Both the in-process stub (Sprint 1, Approach A) and the real FFI
// binding (Sprint 2, Approach B) conform to these protocols. The
// surface is locked to python's `octomil/runtime/native/loader.py`
// `_CDEF` block at lines 359–648; changes here require a matched
// python change first.
//
// Spec: docs/specs/2026-05-06-ios-stub-runtime.md

import Foundation

// MARK: - ABI version

/// Pinned ABI version this binding targets. The FFI path performs a
/// handshake at load (pin major exact, minor ≥ required) and fails fast
/// with `.versionMismatch` on drift; the stub ignores this but keeps it
/// here to document intent for Approach B.
public enum NativeABI {
    public static let requiredMajor: UInt32 = 0
    public static let requiredMinor: UInt32 = 7
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

public struct NativeTranscriptChunkPayload: Sendable {
    public let utf8: String

    public init(utf8: String) {
        self.utf8 = utf8
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
    case turnEnded(envelope: NativeOperationalEnvelope)
    case error(NativeErrorPayload, envelope: NativeOperationalEnvelope)
    case sessionCompleted(NativeSessionCompletedPayload, envelope: NativeOperationalEnvelope)
    case modelLoaded(NativeModelLoadedPayload, envelope: NativeOperationalEnvelope)

    public var envelope: NativeOperationalEnvelope {
        switch self {
        case .sessionStarted(_, let env),
             .audioChunk(_, let env),
             .transcriptChunk(_, let env),
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

    /// Precondition: all models opened via this runtime have been
    /// closed first. Violation triggers a precondition failure.
    func close() async
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

    /// Returns the next event. Returns nil on TIMEOUT (mirrors the C
    /// `OCT_STATUS_TIMEOUT` + `out->type = OCT_EVENT_NONE` convention).
    func pollEvent(timeout: TimeInterval) async throws -> NativeEvent?

    func cancel() async throws
    func close() async
}

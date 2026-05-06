// In-process stub conforming to NativeRuntime / NativeModel /
// NativeSession. Approach A from docs/spikes/2026-05-06-ios-xcframework-spike.md.
// Approach B (real FFI) will replace these types; UI / canary /
// telemetry consumers built against the protocols don't rework.
//
// Sprint 1 (OCT-104 sub-issue A): unblocks the iPad demo's lifecycle +
// telemetry path without compiling octomil-runtime to iOS.

import Foundation

// MARK: - StubRuntime

public actor StubRuntime: NativeRuntime {
    private let config: NativeRuntimeConfig
    private let telemetrySink: NativeTelemetrySink?
    private var openModelIDs: Set<ObjectIdentifier> = []
    private var isClosed = false

    public init(config: NativeRuntimeConfig, telemetrySink: NativeTelemetrySink?) {
        self.config = config
        self.telemetrySink = telemetrySink
    }

    public static func open(
        config: NativeRuntimeConfig,
        telemetrySink: NativeTelemetrySink?
    ) async throws -> Self {
        Self(config: config, telemetrySink: telemetrySink)
    }

    public func capabilities() async throws -> NativeCapabilities {
        try checkOpen()
        return NativeCapabilities(
            supportedEngines: ["llama_cpp", "sherpa-onnx", "whisper.cpp", "coreml", "mlx"],
            supportedCapabilities: ["chat.completion", "asr.streaming", "tts.streaming"],
            supportedArchs: ["arm64"],
            ramTotalBytes: UInt64(16) * 1024 * 1024 * 1024,
            ramAvailableBytes: UInt64(8) * 1024 * 1024 * 1024,
            hasAppleSilicon: true,
            hasCUDA: false,
            hasMetal: true
        )
    }

    public func openModel(config modelConfig: NativeModelConfig) async throws -> any NativeModel {
        try checkOpen()
        let model = StubModel(config: modelConfig, owner: self)
        openModelIDs.insert(ObjectIdentifier(model))

        // Fire MODEL_LOADED via the telemetry sink. The C runtime emits
        // this asynchronously after warm completes; the stub fires it
        // synchronously since warm is a no-op.
        let payload = NativeModelLoadedPayload(
            engine: modelConfig.engineHint ?? "llama_cpp",
            modelID: modelConfig.modelURI,
            artifactDigest: modelConfig.artifactDigest,
            loadMs: 250,
            warmMs: 80,
            policyPreset: modelConfig.policyPreset ?? "",
            source: "stub"
        )
        let envelope = NativeOperationalEnvelope(
            engineVersion: "stub-1.0",
            adapterVersion: "stub-1.0",
            accelerator: "metal",
            artifactDigest: modelConfig.artifactDigest
        )
        telemetrySink?(.modelLoaded(payload, envelope: envelope))

        return model
    }

    public func openSession(
        config sessionConfig: NativeSessionConfig,
        model: any NativeModel
    ) async throws -> any NativeSession {
        try checkOpen()
        // Cross-runtime model check (binding trap from
        // project_runtime_abi_bindings.md, item 7). Defense-in-depth:
        // surfaces a precise typed error instead of letting a foreign
        // model handle reach a real FFI call later.
        guard let stubModel = model as? StubModel else {
            throw NativeRuntimeError(status: .invalidInput, message: "model is not a StubModel")
        }
        guard await stubModel.isOwnedBy(self) else {
            throw NativeRuntimeError(status: .invalidInput, message: "model belongs to a different runtime")
        }

        await stubModel.borrow()
        let digest = await stubModel.artifactDigest

        return StubSession(
            config: sessionConfig,
            model: stubModel,
            artifactDigest: digest
        )
    }

    public func close() async {
        precondition(
            openModelIDs.isEmpty,
            "StubRuntime.close() called with \(openModelIDs.count) open model(s) — close models first."
        )
        isClosed = true
    }

    // Called by StubModel.close() after a successful BUSY-free close.
    func unregisterModel(_ model: StubModel) {
        openModelIDs.remove(ObjectIdentifier(model))
    }

    private func checkOpen() throws {
        if isClosed {
            throw NativeRuntimeError(status: .invalidInput, message: "runtime is closed")
        }
    }
}

// MARK: - StubModel

public actor StubModel: NativeModel {
    let config: NativeModelConfig
    private weak var owner: StubRuntime?
    private var borrowCount: Int = 0
    private var isClosed = false

    var artifactDigest: String { config.artifactDigest }

    init(config: NativeModelConfig, owner: StubRuntime) {
        self.config = config
        self.owner = owner
    }

    public func warm() async throws { try checkOpen() }
    public func evict() async throws { try checkOpen() }

    public func close() async throws {
        try checkOpen()
        if borrowCount > 0 {
            // BUSY: handle remains valid; binding retries after closing
            // sessions. (runtime.h:642-645 / loader.py: oct_model_close.)
            throw NativeRuntimeError(
                status: .busy,
                message: "\(borrowCount) session(s) still borrowing model"
            )
        }
        isClosed = true
        await owner?.unregisterModel(self)
    }

    func borrow() {
        borrowCount += 1
    }

    func release() {
        precondition(borrowCount > 0, "StubModel.release() called with no outstanding borrow")
        borrowCount -= 1
    }

    func isOwnedBy(_ runtime: StubRuntime) -> Bool {
        owner === runtime
    }

    private func checkOpen() throws {
        if isClosed {
            throw NativeRuntimeError(status: .invalidInput, message: "model is closed")
        }
    }
}

// MARK: - StubSession

public actor StubSession: NativeSession {
    private let config: NativeSessionConfig
    private let model: StubModel
    private var script: [NativeEvent]
    private var index: Int = 0
    private var isCancelled = false
    private var isClosed = false
    private var hasReleased = false

    init(
        config: NativeSessionConfig,
        model: StubModel,
        artifactDigest: String,
        script: [NativeEvent]? = nil
    ) {
        self.config = config
        self.model = model
        let envelope = NativeOperationalEnvelope(
            requestID: config.requestID ?? "",
            routeID: config.routeID ?? "",
            traceID: config.traceID ?? "",
            engineVersion: "stub-1.0",
            adapterVersion: "stub-1.0",
            accelerator: "metal",
            artifactDigest: artifactDigest,
            cacheWasHit: false
        )
        self.script = script ?? StubSession.defaultDemoScript(envelope: envelope)
    }

    public func sendAudio(_ pcm: Data, sampleRate: UInt32, channels: UInt16) async throws {
        try checkOpen()
    }

    public func sendText(_ utf8: String) async throws {
        try checkOpen()
    }

    public func pollEvent(timeout: TimeInterval) async throws -> NativeEvent? {
        if isCancelled, index >= script.count {
            // After the cancel completion event has been drained,
            // subsequent polls return CANCELLED (runtime.h: OCT_STATUS_CANCELLED).
            throw NativeRuntimeError(status: .cancelled)
        }
        if isClosed {
            throw NativeRuntimeError(status: .invalidInput)
        }
        if index < script.count {
            let event = script[index]
            index += 1
            return event
        }
        // Script exhausted on a non-cancelled path — sleep then return
        // nil to mirror the C TIMEOUT convention (out->type =
        // OCT_EVENT_NONE, no further events expected).
        if timeout > 0 {
            try? await Task.sleep(for: .seconds(timeout))
        }
        return nil
    }

    public func cancel() async throws {
        try checkOpen()
        isCancelled = true
        let envelope = currentEnvelope()
        let cancelled = NativeSessionCompletedPayload(
            setupMs: 0,
            engineFirstChunkMs: 0,
            e2eFirstChunkMs: 0,
            totalLatencyMs: 0,
            queuedMs: 0,
            observedChunks: UInt32(index),
            capabilityVerified: false,
            terminalStatus: .cancelled
        )
        // Drop remaining script; replace with one CANCELLED completion.
        script = Array(script.prefix(index)) + [.sessionCompleted(cancelled, envelope: envelope)]
    }

    public func close() async {
        if isClosed { return }
        isClosed = true
        if !hasReleased {
            await model.release()
            hasReleased = true
        }
    }

    private func checkOpen() throws {
        if isClosed {
            throw NativeRuntimeError(status: .invalidInput, message: "session is closed")
        }
        if isCancelled {
            throw NativeRuntimeError(status: .cancelled)
        }
    }

    private func currentEnvelope() -> NativeOperationalEnvelope {
        script.first?.envelope ?? NativeOperationalEnvelope()
    }

    // MARK: Default demo timeline

    private static func defaultDemoScript(envelope: NativeOperationalEnvelope) -> [NativeEvent] {
        let started = NativeSessionStartedPayload(
            engine: "llama_cpp",
            modelDigest: envelope.artifactDigest,
            locality: "on-device",
            streamingMode: "streaming",
            runtimeBuildTag: "stub-1.0"
        )
        let transcript1 = NativeTranscriptChunkPayload(utf8: "Patient reports ")
        let transcript2 = NativeTranscriptChunkPayload(utf8: "headache for three days, ")
        let transcript3 = NativeTranscriptChunkPayload(utf8: "intermittent and sharp.")
        // 100 ms of silence at 24 kHz mono float32 = 24000 * 0.1 * 4 bytes.
        let silence = Data(repeating: 0, count: 9600)
        let audio1 = NativeAudioChunkPayload(
            pcm: silence,
            sampleRate: 24000,
            sampleFormat: .pcmF32LE,
            channels: 1,
            isFinal: false
        )
        let audio2 = NativeAudioChunkPayload(
            pcm: silence,
            sampleRate: 24000,
            sampleFormat: .pcmF32LE,
            channels: 1,
            isFinal: false
        )
        let audio3 = NativeAudioChunkPayload(
            pcm: silence,
            sampleRate: 24000,
            sampleFormat: .pcmF32LE,
            channels: 1,
            isFinal: true
        )
        let completed = NativeSessionCompletedPayload(
            setupMs: 42,
            engineFirstChunkMs: 120,
            e2eFirstChunkMs: 180,
            totalLatencyMs: 2340,
            queuedMs: 0,
            observedChunks: 6,
            capabilityVerified: true,
            terminalStatus: .ok
        )
        return [
            .sessionStarted(started, envelope: envelope),
            .transcriptChunk(transcript1, envelope: envelope),
            .transcriptChunk(transcript2, envelope: envelope),
            .transcriptChunk(transcript3, envelope: envelope),
            .turnEnded(envelope: envelope),
            .audioChunk(audio1, envelope: envelope),
            .audioChunk(audio2, envelope: envelope),
            .audioChunk(audio3, envelope: envelope),
            .sessionCompleted(completed, envelope: envelope),
        ]
    }
}

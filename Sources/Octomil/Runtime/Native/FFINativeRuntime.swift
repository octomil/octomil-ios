import COctomilRuntimeBridge
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Dynamic bridge to `liboctomil_runtime`.
///
/// The bridge loads runtime open/capabilities plus the native
/// model/session/event symbols needed for parity tests. It still
/// refuses telemetry sink bridging; that path is separate from the
/// session poll loop and remains unsupported in this slice.
public actor FFINativeRuntime: NativeRuntime {
    public static let libraryPathEnvironmentVariable = "OCTOMIL_RUNTIME_LIBRARY"

    private let library: NativeRuntimeDynamicLibrary
    private var runtimeHandle: UnsafeMutableRawPointer?
    private var isClosed = false
    private var openModels: [FFINativeModel] = []
    private var openSessions: [FFINativeSession] = []

    private init(
        library: NativeRuntimeDynamicLibrary,
        runtimeHandle: UnsafeMutableRawPointer
    ) {
        self.library = library
        self.runtimeHandle = runtimeHandle
    }

    deinit {
        if let handle = runtimeHandle {
            library.runtimeClose(handle)
        }
    }

    public static func open(
        config: NativeRuntimeConfig,
        telemetrySink: NativeTelemetrySink?
    ) async throws -> Self {
        try await open(config: config, telemetrySink: telemetrySink, libraryPath: nil)
    }

    public static func open(
        config: NativeRuntimeConfig,
        telemetrySink: NativeTelemetrySink?,
        libraryPath: String?
    ) async throws -> Self {
        if telemetrySink != nil {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "FFINativeRuntime telemetry/event bridge is not implemented; refusing to drop telemetry."
            )
        }

        let library = try NativeRuntimeDynamicLibrary.load(
            explicitPath: libraryPath,
            environment: ProcessInfo.processInfo.environment
        )
        try library.validateABI()

        var cConfig = oct_runtime_config_t()
        cConfig.version = UInt32(OCT_RUNTIME_CONFIG_VERSION)
        cConfig.telemetry_sink = nil
        cConfig.telemetry_user_data = nil
        cConfig.max_sessions = config.maxSessions

        var openedHandle: UnsafeMutableRawPointer?
        let status = config.artifactRoot.withCString { artifactRoot in
            cConfig.artifact_root = artifactRoot
            return library.runtimeOpen(&cConfig, &openedHandle)
        }

        if status != OCT_STATUS_OK {
            throw library.error(
                status: status,
                operation: "oct_runtime_open",
                runtimeHandle: nil
            )
        }

        guard let openedHandle else {
            throw NativeRuntimeError(
                status: .internalError,
                message: "oct_runtime_open returned OK with a NULL runtime handle."
            )
        }

        return Self(library: library, runtimeHandle: openedHandle)
    }

    public func capabilities() async throws -> NativeCapabilities {
        let handle = try requireOpen(operation: "oct_runtime_capabilities")
        var cCapabilities = oct_capabilities_t()
        cCapabilities.size = MemoryLayout<oct_capabilities_t>.size

        let status = library.runtimeCapabilities(handle, &cCapabilities)
        if status != OCT_STATUS_OK {
            throw library.error(
                status: status,
                operation: "oct_runtime_capabilities",
                runtimeHandle: handle
            )
        }

        defer {
            library.runtimeCapabilitiesFree(&cCapabilities)
        }

        guard cCapabilities.version == UInt32(OCT_CAPABILITIES_VERSION) else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_runtime_capabilities returned version \(cCapabilities.version), expected \(OCT_CAPABILITIES_VERSION)."
            )
        }

        return NativeCapabilities(
            supportedEngines: try copyCStringArray(
                cCapabilities.supported_engines,
                field: "supported_engines"
            ),
            supportedCapabilities: try copyCStringArray(
                cCapabilities.supported_capabilities,
                field: "supported_capabilities"
            ),
            supportedArchs: try copyCStringArray(
                cCapabilities.supported_archs,
                field: "supported_archs"
            ),
            ramTotalBytes: cCapabilities.ram_total_bytes,
            ramAvailableBytes: cCapabilities.ram_available_bytes,
            hasAppleSilicon: cCapabilities.has_apple_silicon != 0,
            hasCUDA: cCapabilities.has_cuda != 0,
            hasMetal: cCapabilities.has_metal != 0
        )
    }

    /// Read the runtime/cache ABI introspection JSON directly from the
    /// native runtime. This is a runtime-scoped ABI call, not a session
    /// lifecycle operation.
    public func cacheIntrospect() async throws -> String {
        let handle = try requireOpen(operation: "oct_runtime_cache_introspect")
        var buffer = [CChar](repeating: 0, count: 4096)
        let status = library.invokeCacheIntrospect(handle, &buffer, buffer.count)
        if status != OCT_STATUS_OK {
            throw library.error(
                status: status,
                operation: "oct_runtime_cache_introspect",
                runtimeHandle: handle
            )
        }

        guard let json = String(validatingUTF8: buffer) else {
            throw NativeRuntimeError(
                status: .internalError,
                message: "oct_runtime_cache_introspect returned non-UTF8 output."
            )
        }

        return json
    }

    public func openModel(config: NativeModelConfig) async throws -> any NativeModel {
        let handle = try requireOpen(operation: "oct_model_open")
        let model = try await FFINativeModel.open(
            runtime: self,
            runtimeHandle: handle,
            library: library,
            config: config
        )
        openModels.append(model)
        return model
    }

    public func openSession(
        config: NativeSessionConfig,
        model: any NativeModel
    ) async throws -> any NativeSession {
        let handle = try requireOpen(operation: "oct_session_open")
        guard let nativeModel = model as? FFINativeModel else {
            throw NativeRuntimeError(
                status: .invalidInput,
                message: "oct_session_open requires a NativeModel created by FFINativeRuntime."
            )
        }
        let session = try await FFINativeSession.open(
            runtime: self,
            runtimeHandle: handle,
            library: library,
            config: config,
            model: nativeModel
        )
        openSessions.append(session)
        return session
    }

    /// Model-free session open: passes ``model = NULL`` in
    /// ``oct_session_config_t``. Used by capabilities that resolve their
    /// artifact from env vars internally (``audio.vad``,
    /// ``audio.diarization``). No ``FFINativeModel`` is kept alive.
    public func openSessionModelFree(config: NativeSessionConfig) async throws -> any NativeSession {
        let handle = try requireOpen(operation: "oct_session_open (model-free)")
        let session = try await FFINativeSession.openModelFree(
            runtime: self,
            runtimeHandle: handle,
            library: library,
            config: config
        )
        openSessions.append(session)
        return session
    }

    public func close() async {
        guard let handle = runtimeHandle else {
            isClosed = true
            return
        }
        let sessions = openSessions
        let models = openModels
        openSessions.removeAll()
        openModels.removeAll()
        runtimeHandle = nil
        isClosed = true
        for session in sessions {
            await session.invalidateAfterRuntimeClose()
        }
        for model in models {
            await model.invalidateAfterRuntimeClose()
        }
        library.runtimeClose(handle)
    }

    fileprivate func unregisterSession(_ session: FFINativeSession) {
        openSessions.removeAll { $0 === session }
    }

    fileprivate func unregisterModel(_ model: FFINativeModel) {
        openModels.removeAll { $0 === model }
    }

    private func requireOpen(operation: String) throws -> UnsafeMutableRawPointer {
        if isClosed {
            throw NativeRuntimeError(
                status: .invalidInput,
                message: "\(operation): runtime is closed"
            )
        }
        guard let runtimeHandle else {
            throw NativeRuntimeError(
                status: .invalidInput,
                message: "\(operation): runtime handle is NULL"
            )
        }
        return runtimeHandle
    }
}

private final class NativeRuntimeDynamicLibrary: @unchecked Sendable {
    fileprivate typealias RuntimeOpen = @convention(c) (
        UnsafePointer<oct_runtime_config_t>?,
        UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> oct_status_t

    fileprivate typealias RuntimeClose = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> Void

    fileprivate typealias RuntimeCapabilities = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<oct_capabilities_t>?
    ) -> oct_status_t

    fileprivate typealias RuntimeCapabilitiesFree = @convention(c) (
        UnsafeMutablePointer<oct_capabilities_t>?
    ) -> Void

    fileprivate typealias ModelOpen = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<oct_model_config_t>?,
        UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> oct_status_t

    fileprivate typealias ModelWarm = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> oct_status_t

    fileprivate typealias ModelEvict = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> oct_status_t

    fileprivate typealias ModelClose = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> oct_status_t

    fileprivate typealias SessionOpen = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<oct_session_config_t>?,
        UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> oct_status_t

    fileprivate typealias SessionClose = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> Void

    fileprivate typealias SessionSendAudio = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<oct_audio_view_t>?
    ) -> oct_status_t

    fileprivate typealias SessionSendText = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> oct_status_t

    fileprivate typealias SessionPollEvent = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<oct_event_t>?,
        UInt32
    ) -> oct_status_t

    fileprivate typealias SessionCancel = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> oct_status_t

    fileprivate typealias RuntimeLastError = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Int32

    fileprivate typealias LastThreadError = @convention(c) (
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Int32

    fileprivate typealias ABIComponent = @convention(c) () -> UInt32
    fileprivate typealias StructSize = @convention(c) () -> Int
    fileprivate typealias CacheClearAll = @convention(c) (UnsafeMutableRawPointer?) -> oct_status_t
    fileprivate typealias CacheClearCapability = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> oct_status_t
    fileprivate typealias CacheClearScope = @convention(c) (
        UnsafeMutableRawPointer?,
        oct_cache_scope_t
    ) -> oct_status_t
    fileprivate typealias CacheIntrospect = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> oct_status_t

    private let libraryHandle: UnsafeMutableRawPointer

    fileprivate let runtimeOpen: RuntimeOpen
    fileprivate let runtimeClose: RuntimeClose
    fileprivate let runtimeCapabilities: RuntimeCapabilities
    fileprivate let runtimeCapabilitiesFree: RuntimeCapabilitiesFree
    fileprivate let modelOpen: ModelOpen
    fileprivate let modelWarm: ModelWarm
    fileprivate let modelEvict: ModelEvict
    fileprivate let modelClose: ModelClose
    fileprivate let sessionOpen: SessionOpen
    fileprivate let sessionClose: SessionClose
    fileprivate let sessionSendAudio: SessionSendAudio
    fileprivate let sessionSendText: SessionSendText
    fileprivate let sessionPollEvent: SessionPollEvent
    fileprivate let sessionCancel: SessionCancel
    private let runtimeLastError: RuntimeLastError
    private let lastThreadError: LastThreadError
    private let abiMajor: ABIComponent
    private let abiMinor: ABIComponent
    private let runtimeConfigSize: StructSize
    private let capabilitiesSize: StructSize
    private let modelConfigSize: StructSize
    private let sessionConfigSize: StructSize
    private let audioViewSize: StructSize
    private let eventSize: StructSize
    private let cacheClearAll: CacheClearAll
    private let cacheClearCapability: CacheClearCapability
    private let cacheClearScope: CacheClearScope
    private let cacheIntrospect: CacheIntrospect

    private init(
        libraryHandle: UnsafeMutableRawPointer,
        runtimeOpen: @escaping RuntimeOpen,
        runtimeClose: @escaping RuntimeClose,
        runtimeCapabilities: @escaping RuntimeCapabilities,
        runtimeCapabilitiesFree: @escaping RuntimeCapabilitiesFree,
        modelOpen: @escaping ModelOpen,
        modelWarm: @escaping ModelWarm,
        modelEvict: @escaping ModelEvict,
        modelClose: @escaping ModelClose,
        sessionOpen: @escaping SessionOpen,
        sessionClose: @escaping SessionClose,
        sessionSendAudio: @escaping SessionSendAudio,
        sessionSendText: @escaping SessionSendText,
        sessionPollEvent: @escaping SessionPollEvent,
        sessionCancel: @escaping SessionCancel,
        runtimeLastError: @escaping RuntimeLastError,
        lastThreadError: @escaping LastThreadError,
        abiMajor: @escaping ABIComponent,
        abiMinor: @escaping ABIComponent,
        runtimeConfigSize: @escaping StructSize,
        capabilitiesSize: @escaping StructSize,
        modelConfigSize: @escaping StructSize,
        sessionConfigSize: @escaping StructSize,
        audioViewSize: @escaping StructSize,
        eventSize: @escaping StructSize,
        cacheClearAll: @escaping CacheClearAll,
        cacheClearCapability: @escaping CacheClearCapability,
        cacheClearScope: @escaping CacheClearScope,
        cacheIntrospect: @escaping CacheIntrospect
    ) {
        self.libraryHandle = libraryHandle
        self.runtimeOpen = runtimeOpen
        self.runtimeClose = runtimeClose
        self.runtimeCapabilities = runtimeCapabilities
        self.runtimeCapabilitiesFree = runtimeCapabilitiesFree
        self.modelOpen = modelOpen
        self.modelWarm = modelWarm
        self.modelEvict = modelEvict
        self.modelClose = modelClose
        self.sessionOpen = sessionOpen
        self.sessionClose = sessionClose
        self.sessionSendAudio = sessionSendAudio
        self.sessionSendText = sessionSendText
        self.sessionPollEvent = sessionPollEvent
        self.sessionCancel = sessionCancel
        self.runtimeLastError = runtimeLastError
        self.lastThreadError = lastThreadError
        self.abiMajor = abiMajor
        self.abiMinor = abiMinor
        self.runtimeConfigSize = runtimeConfigSize
        self.capabilitiesSize = capabilitiesSize
        self.modelConfigSize = modelConfigSize
        self.sessionConfigSize = sessionConfigSize
        self.audioViewSize = audioViewSize
        self.eventSize = eventSize
        self.cacheClearAll = cacheClearAll
        self.cacheClearCapability = cacheClearCapability
        self.cacheClearScope = cacheClearScope
        self.cacheIntrospect = cacheIntrospect
    }

    fileprivate func invokeCacheIntrospect(
        _ runtimeHandle: UnsafeMutableRawPointer?,
        _ buffer: UnsafeMutablePointer<CChar>?,
        _ length: Int
    ) -> oct_status_t {
        cacheIntrospect(runtimeHandle, buffer, length)
    }

    deinit {
        dlclose(libraryHandle)
    }

    fileprivate static func load(
        explicitPath: String?,
        environment: [String: String]
    ) throws -> NativeRuntimeDynamicLibrary {
        let candidates = candidatePaths(explicitPath: explicitPath, environment: environment)
        var diagnostics: [String] = []

        for candidate in candidates {
            let opened = dlopen(candidate, RTLD_NOW | RTLD_LOCAL)
            guard let handle = opened else {
                diagnostics.append("\(candidate): \(currentDLError())")
                continue
            }

            do {
                return try loadSymbols(from: handle)
            } catch {
                dlclose(handle)
                throw error
            }
        }

        let tried = diagnostics.isEmpty ? "no candidate paths" : diagnostics.joined(separator: "; ")
        throw NativeRuntimeError(
            status: .unsupported,
            message: "Native runtime library unavailable. Tried \(tried)."
        )
    }

    fileprivate func validateABI() throws {
        let major = abiMajor()
        let minor = abiMinor()
        guard major == NativeABI.requiredMajor, minor >= NativeABI.requiredMinor else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "Native runtime ABI \(major).\(minor) is incompatible; expected major \(NativeABI.requiredMajor), minor >= \(NativeABI.requiredMinor)."
            )
        }

        let expectedRuntimeConfigSize = MemoryLayout<oct_runtime_config_t>.size
        let actualRuntimeConfigSize = runtimeConfigSize()
        guard actualRuntimeConfigSize == expectedRuntimeConfigSize else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_runtime_config_t size mismatch: dylib=\(actualRuntimeConfigSize), Swift shim=\(expectedRuntimeConfigSize)."
            )
        }

        let expectedCapabilitiesSize = MemoryLayout<oct_capabilities_t>.size
        let actualCapabilitiesSize = capabilitiesSize()
        guard actualCapabilitiesSize == expectedCapabilitiesSize else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_capabilities_t size mismatch: dylib=\(actualCapabilitiesSize), Swift shim=\(expectedCapabilitiesSize)."
            )
        }

        let expectedModelConfigSize = MemoryLayout<oct_model_config_t>.size
        let actualModelConfigSize = modelConfigSize()
        guard actualModelConfigSize == expectedModelConfigSize else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_model_config_t size mismatch: dylib=\(actualModelConfigSize), Swift shim=\(expectedModelConfigSize)."
            )
        }

        let expectedSessionConfigSize = MemoryLayout<oct_session_config_t>.size
        let actualSessionConfigSize = sessionConfigSize()
        guard actualSessionConfigSize == expectedSessionConfigSize else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_session_config_t size mismatch: dylib=\(actualSessionConfigSize), Swift shim=\(expectedSessionConfigSize)."
            )
        }

        let expectedAudioViewSize = MemoryLayout<oct_audio_view_t>.size
        let actualAudioViewSize = audioViewSize()
        guard actualAudioViewSize == expectedAudioViewSize else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_audio_view_t size mismatch: dylib=\(actualAudioViewSize), Swift shim=\(expectedAudioViewSize)."
            )
        }

        let expectedEventSize = MemoryLayout<oct_event_t>.size
        let actualEventSize = eventSize()
        guard actualEventSize == expectedEventSize else {
            throw NativeRuntimeError(
                status: .versionMismatch,
                message: "oct_event_t size mismatch: dylib=\(actualEventSize), Swift shim=\(expectedEventSize)."
            )
        }
    }

    fileprivate func error(
        status: oct_status_t,
        operation: String,
        runtimeHandle: UnsafeMutableRawPointer?
    ) -> NativeRuntimeError {
        let mapped = NativeStatus(rawValue: status) ?? .internalError
        let diagnostic: String?
        if let runtimeHandle {
            diagnostic = readRuntimeLastError(runtimeHandle)
        } else {
            diagnostic = readLastThreadError()
        }
        let suffix = diagnostic.map { ": \($0)" } ?? ""
        return NativeRuntimeError(status: mapped, message: "\(operation) failed\(suffix)")
    }

    private static func candidatePaths(
        explicitPath: String?,
        environment: [String: String]
    ) -> [String] {
        if let explicitPath, !explicitPath.isEmpty {
            return [explicitPath]
        }

        if let envPath = environment[FFINativeRuntime.libraryPathEnvironmentVariable],
           !envPath.isEmpty {
            return [envPath]
        }

        var candidates: [String] = []
        if let privateFrameworksURL = Bundle.main.privateFrameworksURL {
            candidates.append(
                privateFrameworksURL
                    .appendingPathComponent("octomil_runtime.framework")
                    .appendingPathComponent("octomil_runtime")
                    .path
            )
            candidates.append(
                privateFrameworksURL
                    .appendingPathComponent("liboctomil_runtime.dylib")
                    .path
            )
        }

        candidates.append("liboctomil_runtime.dylib")

        #if os(macOS)
        candidates.append("/opt/homebrew/lib/liboctomil_runtime.dylib")
        candidates.append("/usr/local/lib/liboctomil_runtime.dylib")
        #endif

        return candidates
    }

    private static func loadSymbols(
        from handle: UnsafeMutableRawPointer
    ) throws -> NativeRuntimeDynamicLibrary {
        NativeRuntimeDynamicLibrary(
            libraryHandle: handle,
            runtimeOpen: try symbol("oct_runtime_open", from: handle),
            runtimeClose: try symbol("oct_runtime_close", from: handle),
            runtimeCapabilities: try symbol("oct_runtime_capabilities", from: handle),
            runtimeCapabilitiesFree: try symbol("oct_runtime_capabilities_free", from: handle),
            modelOpen: try symbol("oct_model_open", from: handle),
            modelWarm: try symbol("oct_model_warm", from: handle),
            modelEvict: try symbol("oct_model_evict", from: handle),
            modelClose: try symbol("oct_model_close", from: handle),
            sessionOpen: try symbol("oct_session_open", from: handle),
            sessionClose: try symbol("oct_session_close", from: handle),
            sessionSendAudio: try symbol("oct_session_send_audio", from: handle),
            sessionSendText: try symbol("oct_session_send_text", from: handle),
            sessionPollEvent: try symbol("oct_session_poll_event", from: handle),
            sessionCancel: try symbol("oct_session_cancel", from: handle),
            runtimeLastError: try symbol("oct_runtime_last_error", from: handle),
            lastThreadError: try symbol("oct_last_thread_error", from: handle),
            abiMajor: try symbol("oct_runtime_abi_version_major", from: handle),
            abiMinor: try symbol("oct_runtime_abi_version_minor", from: handle),
            runtimeConfigSize: try symbol("oct_runtime_config_size", from: handle),
            capabilitiesSize: try symbol("oct_capabilities_size", from: handle),
            modelConfigSize: try symbol("oct_model_config_size", from: handle),
            sessionConfigSize: try symbol("oct_session_config_size", from: handle),
            audioViewSize: try symbol("oct_audio_view_size", from: handle),
            eventSize: try symbol("oct_event_size", from: handle),
            cacheClearAll: try symbol("oct_runtime_cache_clear_all", from: handle),
            cacheClearCapability: try symbol("oct_runtime_cache_clear_capability", from: handle),
            cacheClearScope: try symbol("oct_runtime_cache_clear_scope", from: handle),
            cacheIntrospect: try symbol("oct_runtime_cache_introspect", from: handle)
        )
    }

    private static func symbol<T>(
        _ name: String,
        from handle: UnsafeMutableRawPointer
    ) throws -> T {
        guard let raw = dlsym(handle, name) else {
            throw NativeRuntimeError(
                status: .unsupported,
                message: "Native runtime symbol \(name) unavailable: \(currentDLError())."
            )
        }
        return unsafeBitCast(raw, to: T.self)
    }

    private func readRuntimeLastError(_ runtimeHandle: UnsafeMutableRawPointer) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let written = runtimeLastError(runtimeHandle, &buffer, buffer.count)
        return Self.message(from: buffer, written: written)
    }

    private func readLastThreadError() -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let written = lastThreadError(&buffer, buffer.count)
        return Self.message(from: buffer, written: written)
    }

    private static func message(from buffer: [CChar], written: Int32) -> String? {
        guard written > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func currentDLError() -> String {
        guard let message = dlerror() else { return "unknown dlerror" }
        return String(cString: message)
    }
}

private func copyCStringArray(
    _ pointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
    field: String
) throws -> [String] {
    guard let pointer else {
        throw NativeRuntimeError(
            status: .internalError,
            message: "oct_runtime_capabilities returned NULL \(field)."
        )
    }

    var values: [String] = []
    var index = 0
    while true {
        guard index < 4096 else {
            throw NativeRuntimeError(
                status: .internalError,
                message: "oct_runtime_capabilities \(field) was not NULL-terminated within 4096 entries."
            )
        }
        guard let cString = pointer[index] else {
            return values
        }
        values.append(String(cString: cString))
        index += 1
    }
}

private enum NativeEventTag: UInt32 {
    case none = 0
    case sessionStarted = 1
    case audioChunk = 2
    case transcriptChunk = 3
    case turnEnded = 5
    case error = 7
    case sessionCompleted = 8
    case modelLoaded = 10
    case modelEvicted = 11
    case cacheHit = 12
    case cacheMiss = 13
    case metric = 19
    case embeddingVector = 20
    case transcriptSegment = 21
    case transcriptFinal = 22
    case ttsAudioChunk = 23
    case vadTransition = 24
    case diarizationSegment = 25
}

private func optionalCString(_ pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer else { return "" }
    return String(cString: pointer)
}

private func withOptionalCString<T>(
    _ string: String?,
    _ body: (UnsafePointer<CChar>?) throws -> T
) rethrows -> T {
    guard let string else {
        return try body(nil)
    }
    return try string.withCString { pointer in
        try body(pointer)
    }
}

public actor FFINativeModel: NativeModel {
    private weak var runtime: FFINativeRuntime?
    private let library: NativeRuntimeDynamicLibrary
    private var runtimeHandle: UnsafeMutableRawPointer?
    private var modelHandle: UnsafeMutableRawPointer?
    private var borrowCount: Int = 0
    private var isClosed = false

    fileprivate init(
        runtime: FFINativeRuntime,
        runtimeHandle: UnsafeMutableRawPointer,
        library: NativeRuntimeDynamicLibrary,
        modelHandle: UnsafeMutableRawPointer?
    ) {
        self.runtime = runtime
        self.runtimeHandle = runtimeHandle
        self.library = library
        self.modelHandle = modelHandle
    }

    fileprivate static func open(
        runtime: FFINativeRuntime,
        runtimeHandle: UnsafeMutableRawPointer,
        library: NativeRuntimeDynamicLibrary,
        config: NativeModelConfig
    ) async throws -> FFINativeModel {
        var cConfig = oct_model_config_t()
        cConfig.version = UInt32(OCT_MODEL_CONFIG_VERSION)
        cConfig.accelerator_pref = config.acceleratorPref
        cConfig.ram_budget_bytes = config.ramBudgetBytes

        var openedHandle: UnsafeMutableRawPointer?
        let status = try config.modelURI.withCString { modelURI in
            cConfig.model_uri = modelURI
            return try config.artifactDigest.withCString { artifactDigest in
                cConfig.artifact_digest = artifactDigest
                return try withOptionalCString(config.engineHint) { engineHint in
                    cConfig.engine_hint = engineHint
                    return try withOptionalCString(config.policyPreset) { policyPreset in
                        cConfig.policy_preset = policyPreset
                        return library.modelOpen(runtimeHandle, &cConfig, &openedHandle)
                    }
                }
            }
        }

        guard status == OCT_STATUS_OK, let openedHandle else {
            throw library.error(
                status: status,
                operation: "oct_model_open",
                runtimeHandle: runtimeHandle
            )
        }

        return FFINativeModel(
            runtime: runtime,
            runtimeHandle: runtimeHandle,
            library: library,
            modelHandle: openedHandle
        )
    }

    fileprivate func runtimeModelHandle() throws -> UnsafeMutableRawPointer {
        try checkOpen()
        guard let handle = modelHandle else {
            throw NativeRuntimeError(status: .invalidInput, message: "model handle is NULL")
        }
        return handle
    }

    public func warm() async throws {
        let handle = try runtimeModelHandle()
        let status = library.modelWarm(handle)
        guard status == OCT_STATUS_OK else {
            throw library.error(status: status, operation: "oct_model_warm", runtimeHandle: runtimeHandle)
        }
    }

    public func evict() async throws {
        let handle = try runtimeModelHandle()
        let status = library.modelEvict(handle)
        guard status == OCT_STATUS_OK || status == OCT_STATUS_UNSUPPORTED || status == OCT_STATUS_BUSY else {
            throw library.error(status: status, operation: "oct_model_evict", runtimeHandle: runtimeHandle)
        }
    }

    public func close() async throws {
        if isClosed {
            return
        }
        guard let handle = modelHandle else {
            isClosed = true
            return
        }
        if runtimeHandle == nil {
            isClosed = true
            modelHandle = nil
            return
        }
        let status = library.modelClose(handle)
        if status == OCT_STATUS_OK {
            isClosed = true
            modelHandle = nil
            await runtime?.unregisterModel(self)
            return
        }
        if status == OCT_STATUS_BUSY {
            return
        }
        throw library.error(status: status, operation: "oct_model_close", runtimeHandle: runtimeHandle)
    }

    fileprivate func borrow() async {
        borrowCount += 1
    }

    fileprivate func release() async {
        if borrowCount > 0 {
            borrowCount -= 1
        }
    }

    fileprivate func invalidateAfterRuntimeClose() async {
        runtimeHandle = nil
        modelHandle = nil
        isClosed = true
        borrowCount = 0
    }

    private func checkOpen() throws {
        if isClosed {
            throw NativeRuntimeError(status: .invalidInput, message: "model is closed")
        }
        if runtimeHandle == nil {
            throw NativeRuntimeError(status: .invalidInput, message: "model handle invalidated")
        }
    }
}

public actor FFINativeSession: NativeSession {
    private weak var runtime: FFINativeRuntime?
    private let library: NativeRuntimeDynamicLibrary
    private var runtimeHandle: UnsafeMutableRawPointer?
    private var sessionHandle: UnsafeMutableRawPointer?
    /// `nil` for model-free sessions (``audio.vad``, ``audio.diarization``).
    private let borrowedModel: FFINativeModel?
    private var isClosed = false
    private var isInvalidated = false
    private var hasReleasedModel = false

    fileprivate init(
        runtime: FFINativeRuntime,
        runtimeHandle: UnsafeMutableRawPointer,
        library: NativeRuntimeDynamicLibrary,
        sessionHandle: UnsafeMutableRawPointer,
        borrowedModel: FFINativeModel?
    ) {
        self.runtime = runtime
        self.runtimeHandle = runtimeHandle
        self.library = library
        self.sessionHandle = sessionHandle
        self.borrowedModel = borrowedModel
    }

    fileprivate static func open(
        runtime: FFINativeRuntime,
        runtimeHandle: UnsafeMutableRawPointer,
        library: NativeRuntimeDynamicLibrary,
        config: NativeSessionConfig,
        model: FFINativeModel
    ) async throws -> FFINativeSession {
        let modelHandle = try await model.runtimeModelHandle()
        let session = try await openCore(
            runtime: runtime,
            runtimeHandle: runtimeHandle,
            library: library,
            config: config,
            modelHandle: modelHandle
        )
        await model.borrow()
        return FFINativeSession(
            runtime: runtime,
            runtimeHandle: runtimeHandle,
            library: library,
            sessionHandle: session,
            borrowedModel: model
        )
    }

    /// Model-free session open: passes ``model = NULL`` in
    /// ``oct_session_config_t``. The C runtime's capability adapter
    /// resolves its artifact from env vars.
    fileprivate static func openModelFree(
        runtime: FFINativeRuntime,
        runtimeHandle: UnsafeMutableRawPointer,
        library: NativeRuntimeDynamicLibrary,
        config: NativeSessionConfig
    ) async throws -> FFINativeSession {
        let sessionHandle = try await openCore(
            runtime: runtime,
            runtimeHandle: runtimeHandle,
            library: library,
            config: config,
            modelHandle: nil
        )
        return FFINativeSession(
            runtime: runtime,
            runtimeHandle: runtimeHandle,
            library: library,
            sessionHandle: sessionHandle,
            borrowedModel: nil
        )
    }

    /// Shared C-ABI session-open path. Pass ``modelHandle = nil`` for
    /// model-free sessions (``oct_session_config_t.model`` stays NULL).
    private static func openCore(
        runtime: FFINativeRuntime,
        runtimeHandle: UnsafeMutableRawPointer,
        library: NativeRuntimeDynamicLibrary,
        config: NativeSessionConfig,
        modelHandle: UnsafeMutableRawPointer?
    ) async throws -> UnsafeMutableRawPointer {
        var cConfig = oct_session_config_t()
        cConfig.version = UInt32(OCT_SESSION_CONFIG_VERSION)
        cConfig.priority = config.priority.rawValue
        cConfig.sample_rate_in = config.sampleRateIn
        cConfig.sample_rate_out = config.sampleRateOut
        cConfig.model = modelHandle.map { OpaquePointer($0) }

        var openedHandle: UnsafeMutableRawPointer?
        let status = try config.modelURI.withCString { modelURI in
            cConfig.model_uri = modelURI
            return try config.capability.withCString { capability in
                cConfig.capability = capability
                return try config.locality.withCString { locality in
                    cConfig.locality = locality
                    return try withOptionalCString(config.policyPreset) { policyPreset in
                        cConfig.policy_preset = policyPreset
                        return try withOptionalCString(config.speakerID) { speakerID in
                            cConfig.speaker_id = speakerID
                            return try withOptionalCString(config.requestID) { requestID in
                                cConfig.request_id = requestID
                                return try withOptionalCString(config.routeID) { routeID in
                                    cConfig.route_id = routeID
                                    return try withOptionalCString(config.traceID) { traceID in
                                        cConfig.trace_id = traceID
                                        return try withOptionalCString(config.kvPrefixKey) { kvPrefixKey in
                                            cConfig.kv_prefix_key = kvPrefixKey
                                            return library.sessionOpen(runtimeHandle, &cConfig, &openedHandle)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard status == OCT_STATUS_OK, let openedHandle else {
            throw library.error(
                status: status,
                operation: "oct_session_open",
                runtimeHandle: runtimeHandle
            )
        }
        return openedHandle
    }

    public func sendAudio(_ pcm: Data, sampleRate: UInt32, channels: UInt16) async throws {
        try checkOpen()
        guard channels > 0, sampleRate > 0, pcm.count % 4 == 0 else {
            throw NativeRuntimeError(status: .invalidInput, message: "invalid audio buffer")
        }
        let status = try pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return OCT_STATUS_INVALID_INPUT
            }
            var view = oct_audio_view_t()
            view.samples = base.assumingMemoryBound(to: Float.self)
            view.n_frames = UInt32((pcm.count / 4) / Int(channels))
            view.sample_rate = sampleRate
            view.channels = channels
            view._reserved0 = 0
            return library.sessionSendAudio(sessionHandle, &view)
        }
        guard status == OCT_STATUS_OK else {
            throw library.error(status: status, operation: "oct_session_send_audio", runtimeHandle: runtimeHandle)
        }
    }

    public func sendText(_ utf8: String) async throws {
        try checkOpen()
        let status = utf8.withCString { pointer in
            library.sessionSendText(sessionHandle, pointer)
        }
        guard status == OCT_STATUS_OK else {
            throw library.error(status: status, operation: "oct_session_send_text", runtimeHandle: runtimeHandle)
        }
    }

    public func pollEvent(timeout: TimeInterval) async throws -> NativeEvent? {
        try checkOpen()
        var event = oct_event_t()
        event.version = UInt32(OCT_EVENT_VERSION)
        event.size = MemoryLayout<oct_event_t>.size
        let timeoutMs = UInt32(max(0, min(timeout * 1000.0, Double(UInt32.max))))
        let status = library.sessionPollEvent(sessionHandle, &event, timeoutMs)
        if status == OCT_STATUS_TIMEOUT {
            return nil
        }
        guard status == OCT_STATUS_OK else {
            throw library.error(status: status, operation: "oct_session_poll_event", runtimeHandle: runtimeHandle)
        }
        return NativeEvent.from(event)
    }

    public func cancel() async throws {
        try checkOpen()
        let status = library.sessionCancel(sessionHandle)
        guard status == OCT_STATUS_OK || status == OCT_STATUS_CANCELLED || status == OCT_STATUS_UNSUPPORTED else {
            throw library.error(status: status, operation: "oct_session_cancel", runtimeHandle: runtimeHandle)
        }
    }

    public func close() async {
        if isClosed {
            return
        }
        isClosed = true
        if !hasReleasedModel {
            await borrowedModel?.release()
            hasReleasedModel = true
        }
        guard !isInvalidated, let handle = sessionHandle else {
            sessionHandle = nil
            await runtime?.unregisterSession(self)
            return
        }
        library.sessionClose(handle)
        sessionHandle = nil
        await runtime?.unregisterSession(self)
    }

    fileprivate func invalidateAfterRuntimeClose() async {
        isInvalidated = true
        isClosed = true
        if !hasReleasedModel {
            await borrowedModel?.release()
            hasReleasedModel = true
        }
        sessionHandle = nil
        runtimeHandle = nil
    }

    private func checkOpen() throws {
        if isClosed {
            throw NativeRuntimeError(status: .invalidInput, message: "session is closed")
        }
        if isInvalidated || runtimeHandle == nil || sessionHandle == nil {
            throw NativeRuntimeError(status: .invalidInput, message: "session handle invalidated")
        }
    }
}

private extension NativeEvent {
    static func from(_ event: oct_event_t) -> NativeEvent? {
        let envelope = NativeOperationalEnvelope(
            requestID: optionalCString(event.request_id),
            routeID: optionalCString(event.route_id),
            traceID: optionalCString(event.trace_id),
            engineVersion: optionalCString(event.engine_version),
            adapterVersion: optionalCString(event.adapter_version),
            accelerator: optionalCString(event.accelerator),
            artifactDigest: optionalCString(event.artifact_digest),
            cacheWasHit: event.cache_was_hit != 0
        )

        guard let tag = NativeEventTag(rawValue: event.type) else {
            return nil
        }

        switch tag {
        case .none:
            return nil
        case .sessionStarted:
            let payload = event.data.session_started
            return .sessionStarted(
                NativeSessionStartedPayload(
                    engine: optionalCString(payload.engine),
                    modelDigest: optionalCString(payload.model_digest),
                    locality: optionalCString(payload.locality),
                    streamingMode: optionalCString(payload.streaming_mode),
                    runtimeBuildTag: optionalCString(payload.runtime_build_tag)
                ),
                envelope: envelope
            )
        case .audioChunk:
            let payload = event.data.audio_chunk
            let data = payload.n_bytes > 0 && payload.pcm != nil
                ? Data(bytes: payload.pcm!, count: Int(payload.n_bytes))
                : Data()
            return .audioChunk(
                NativeAudioChunkPayload(
                    pcm: data,
                    sampleRate: payload.sample_rate,
                    sampleFormat: NativeSampleFormat(rawValue: payload.sample_format) ?? .pcmF32LE,
                    channels: payload.channels,
                    isFinal: payload.is_final != 0
                ),
                envelope: envelope
            )
        case .transcriptChunk:
            let payload = event.data.transcript_chunk
            return .transcriptChunk(
                NativeTranscriptChunkPayload(utf8: optionalCString(payload.utf8)),
                envelope: envelope
            )
        case .turnEnded:
            return .turnEnded(envelope: envelope)
        case .error:
            let payload = event.data.error
            return .error(
                NativeErrorPayload(
                    code: optionalCString(payload.code),
                    message: optionalCString(payload.message),
                    errorCode: payload.error_code
                ),
                envelope: envelope
            )
        case .sessionCompleted:
            let payload = event.data.session_completed
            return .sessionCompleted(
                NativeSessionCompletedPayload(
                    setupMs: payload.setup_ms,
                    engineFirstChunkMs: payload.engine_first_chunk_ms,
                    e2eFirstChunkMs: payload.e2e_first_chunk_ms,
                    totalLatencyMs: payload.total_latency_ms,
                    queuedMs: payload.queued_ms,
                    observedChunks: payload.observed_chunks,
                    capabilityVerified: payload.capability_verified != 0,
                    terminalStatus: NativeStatus(rawValue: payload.terminal_status) ?? .internalError
                ),
                envelope: envelope
            )
        case .modelLoaded:
            let payload = event.data.model_loaded
            return .modelLoaded(
                NativeModelLoadedPayload(
                    engine: optionalCString(payload.engine),
                    modelID: optionalCString(payload.model_id),
                    artifactDigest: optionalCString(payload.artifact_digest),
                    loadMs: payload.load_ms,
                    warmMs: payload.warm_ms,
                    policyPreset: optionalCString(payload.policy_preset),
                    source: optionalCString(payload.source)
                ),
                envelope: envelope
            )
        case .modelEvicted:
            return nil
        case .cacheHit, .cacheMiss:
            let payload = event.data.cache
            let cachePayload = NativeCachePayload(
                layer: optionalCString(payload.layer),
                savedTokens: payload.saved_tokens
            )
            return tag == .cacheHit
                ? .cacheHit(cachePayload, envelope: envelope)
                : .cacheMiss(cachePayload, envelope: envelope)
        case .metric:
            return nil
        case .embeddingVector:
            let payload = event.data.embedding_vector
            let count = Int(payload.n_dim)
            let values: [Float]
            if count > 0 {
                let buffer = UnsafeBufferPointer(start: payload.values, count: count)
                values = Array(buffer)
            } else {
                values = []
            }
            return .embeddingVector(
                NativeEmbeddingVectorPayload(
                    values: values,
                    dimension: payload.n_dim,
                    inputTokens: payload.n_input_tokens,
                    index: payload.index,
                    poolingType: payload.pooling_type,
                    isNormalized: payload.is_normalized != 0
                ),
                envelope: envelope
            )
        case .transcriptSegment:
            let payload = event.data.transcript_segment
            return .transcriptSegment(
                NativeTranscriptSegmentPayload(
                    utf8: optionalCString(payload.utf8),
                    nBytes: payload.n_bytes,
                    startMs: payload.start_ms,
                    endMs: payload.end_ms,
                    segmentIndex: payload.segment_index,
                    isFinal: payload.is_final != 0
                ),
                envelope: envelope
            )
        case .transcriptFinal:
            let payload = event.data.transcript_final
            return .transcriptFinal(
                NativeTranscriptFinalPayload(
                    utf8: optionalCString(payload.utf8),
                    nBytes: payload.n_bytes,
                    nSegments: payload.n_segments,
                    durationMs: payload.duration_ms
                ),
                envelope: envelope
            )
        case .ttsAudioChunk:
            let payload = event.data.tts_audio_chunk
            let data = payload.n_bytes > 0 && payload.pcm != nil
                ? Data(bytes: payload.pcm!, count: Int(payload.n_bytes))
                : Data()
            return .ttsAudioChunk(
                NativeAudioChunkPayload(
                    pcm: data,
                    sampleRate: payload.sample_rate,
                    sampleFormat: NativeSampleFormat(rawValue: payload.sample_format) ?? .pcmF32LE,
                    channels: payload.channels,
                    isFinal: payload.is_final != 0
                ),
                envelope: envelope
            )
        case .vadTransition:
            let payload = event.data.vad_transition
            return .vadTransition(
                NativeVADTransitionPayload(
                    transitionKind: payload.transition_kind,
                    timestampMs: payload.timestamp_ms,
                    confidence: payload.confidence
                ),
                envelope: envelope
            )
        case .diarizationSegment:
            let payload = event.data.diarization_segment
            return .diarizationSegment(
                NativeDiarizationSegmentPayload(
                    startMs: payload.start_ms,
                    endMs: payload.end_ms,
                    speakerID: payload.speaker_id,
                    speakerLabel: optionalCString(payload.speaker_label)
                ),
                envelope: envelope
            )
        }
    }
}

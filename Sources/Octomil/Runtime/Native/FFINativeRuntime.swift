import COctomilRuntimeBridge
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Minimal dynamic bridge to `liboctomil_runtime`.
///
/// This actor intentionally wires only runtime open, capability discovery,
/// ABI/struct-size validation, close, and status/last-error surfacing.
/// Model/session/event operations remain unsupported until their C bindings
/// are implemented and covered by native lifecycle tests.
public actor FFINativeRuntime: NativeRuntime {
    public static let libraryPathEnvironmentVariable = "OCTOMIL_RUNTIME_LIBRARY"

    private let library: NativeRuntimeDynamicLibrary
    private var runtimeHandle: UnsafeMutableRawPointer?
    private var isClosed = false

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

    public func openModel(config: NativeModelConfig) async throws -> any NativeModel {
        _ = try requireOpen(operation: "oct_model_open")
        throw NativeRuntimeError(
            status: .unsupported,
            message: "FFINativeRuntime model bridge is not implemented."
        )
    }

    public func openSession(
        config: NativeSessionConfig,
        model: any NativeModel
    ) async throws -> any NativeSession {
        _ = try requireOpen(operation: "oct_session_open")
        throw NativeRuntimeError(
            status: .unsupported,
            message: "FFINativeRuntime session/event bridge is not implemented."
        )
    }

    public func close() async {
        guard let handle = runtimeHandle else {
            isClosed = true
            return
        }
        runtimeHandle = nil
        isClosed = true
        library.runtimeClose(handle)
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

    private let libraryHandle: UnsafeMutableRawPointer

    fileprivate let runtimeOpen: RuntimeOpen
    fileprivate let runtimeClose: RuntimeClose
    fileprivate let runtimeCapabilities: RuntimeCapabilities
    fileprivate let runtimeCapabilitiesFree: RuntimeCapabilitiesFree
    private let runtimeLastError: RuntimeLastError
    private let lastThreadError: LastThreadError
    private let abiMajor: ABIComponent
    private let abiMinor: ABIComponent
    private let runtimeConfigSize: StructSize
    private let capabilitiesSize: StructSize

    private init(
        libraryHandle: UnsafeMutableRawPointer,
        runtimeOpen: @escaping RuntimeOpen,
        runtimeClose: @escaping RuntimeClose,
        runtimeCapabilities: @escaping RuntimeCapabilities,
        runtimeCapabilitiesFree: @escaping RuntimeCapabilitiesFree,
        runtimeLastError: @escaping RuntimeLastError,
        lastThreadError: @escaping LastThreadError,
        abiMajor: @escaping ABIComponent,
        abiMinor: @escaping ABIComponent,
        runtimeConfigSize: @escaping StructSize,
        capabilitiesSize: @escaping StructSize
    ) {
        self.libraryHandle = libraryHandle
        self.runtimeOpen = runtimeOpen
        self.runtimeClose = runtimeClose
        self.runtimeCapabilities = runtimeCapabilities
        self.runtimeCapabilitiesFree = runtimeCapabilitiesFree
        self.runtimeLastError = runtimeLastError
        self.lastThreadError = lastThreadError
        self.abiMajor = abiMajor
        self.abiMinor = abiMinor
        self.runtimeConfigSize = runtimeConfigSize
        self.capabilitiesSize = capabilitiesSize
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
            runtimeLastError: try symbol("oct_runtime_last_error", from: handle),
            lastThreadError: try symbol("oct_last_thread_error", from: handle),
            abiMajor: try symbol("oct_runtime_abi_version_major", from: handle),
            abiMinor: try symbol("oct_runtime_abi_version_minor", from: handle),
            runtimeConfigSize: try symbol("oct_runtime_config_size", from: handle),
            capabilitiesSize: try symbol("oct_capabilities_size", from: handle)
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

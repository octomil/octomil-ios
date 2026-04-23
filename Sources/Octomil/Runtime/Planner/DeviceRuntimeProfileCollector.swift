import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Collects the device runtime profile for planner requests.
///
/// Gathers SDK version, platform details, hardware specs, and available
/// inference engines without exposing any user data (prompts, paths, etc.).
public enum DeviceRuntimeProfileCollector {

    // MARK: - Public API

    /// Collect a full device runtime profile for the current device.
    ///
    /// - Parameter additionalRuntimes: Extra runtimes detected by extension
    ///   modules (e.g. OctomilMLX, OctomilRuntimeLlama) that are not part
    ///   of the core SDK. Pass these in from the umbrella target.
    /// - Returns: A populated ``DeviceRuntimeProfile``.
    public static func collect(
        additionalRuntimes: [InstalledRuntime] = []
    ) -> DeviceRuntimeProfile {
        var runtimes = detectCoreRuntimes()
        runtimes.append(contentsOf: additionalRuntimes.map {
            InstalledRuntime(
                engine: $0.engine,
                version: $0.version,
                available: $0.available,
                accelerator: $0.accelerator,
                metadata: $0.metadata
            )
        })

        return DeviceRuntimeProfile(
            sdk: "ios",
            sdkVersion: OctomilVersion.current,
            platform: platformName(),
            arch: cpuArchitecture(),
            osVersion: osVersion(),
            chip: machineIdentifier(),
            ramTotalBytes: totalRAMBytes(),
            gpuCoreCount: nil, // Not reliably queryable on iOS
            accelerators: detectAccelerators(),
            installedRuntimes: runtimes,
            supportedGateCodes: []
        )
    }

    // MARK: - Platform

    static func platformName() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }

    static func cpuArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static func osVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// Returns the machine identifier (e.g. "iPhone16,1", "MacBookPro18,1").
    ///
    /// Does NOT return user-visible device names or identifiers that could
    /// fingerprint a specific user's device.
    static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    // MARK: - Hardware

    static func totalRAMBytes() -> Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    // MARK: - Accelerators

    static func detectAccelerators() -> [String] {
        var accels: [String] = []

        // All Apple Silicon has Metal
        #if arch(arm64)
        accels.append("metal")
        #endif

        // Neural Engine is present on A11+ / all Apple Silicon Macs.
        // There is no public API to query this directly; use arch as proxy.
        #if arch(arm64)
        accels.append("ane")
        #endif

        return accels
    }

    // MARK: - Installed Runtimes

    /// Detect inference engines that ship with the core SDK.
    ///
    /// CoreML framework availability is not the same as having a model-capable
    /// Octomil runtime installed. Extension-module engines (CoreML model
    /// adapters, MLX, llama.cpp, etc.) must be passed in
    /// via `additionalRuntimes` because the core `Octomil` target does not
    /// link against those binary frameworks.
    static func detectCoreRuntimes() -> [InstalledRuntime] {
        []
    }
}

import Foundation
import os.log

/// A snapshot of the current device's hardware and ML capabilities.
///
/// Combines data from ``DeviceMetadata`` and ``PairingDeviceCapabilities``
/// into a single unified profile.
///
/// Access via ``OctomilClient/capabilities``:
///
/// ```swift
/// let profile = client.capabilities.current()
/// print(profile.deviceClass)      // .high
/// print(profile.memoryMb)         // 8192
/// print(profile.availableRuntimes) // ["coreml"]
/// ```
public struct CapabilityProfile: Sendable {
    /// Device performance tier.
    public let deviceClass: DeviceClass
    /// Runtimes available on this device (e.g. `["coreml"]`, `["coreml", "mlx"]`).
    public let availableRuntimes: [String]
    /// Total physical memory in megabytes.
    public let memoryMb: Int
    /// Available storage in megabytes, or `nil` if unavailable.
    public let storageMb: Int?
    /// Platform identifier (e.g. "ios", "macos").
    public let platform: String
    /// Hardware accelerators present on the device.
    public let accelerators: [String]

    public init(
        deviceClass: DeviceClass,
        availableRuntimes: [String],
        memoryMb: Int,
        storageMb: Int?,
        platform: String,
        accelerators: [String]
    ) {
        self.deviceClass = deviceClass
        self.availableRuntimes = availableRuntimes
        self.memoryMb = memoryMb
        self.storageMb = storageMb
        self.platform = platform
        self.accelerators = accelerators
    }
}

/// Namespace client for querying device capabilities.
///
/// Access via ``OctomilClient/capabilities``.
public final class CapabilitiesClient: Sendable {

    // MARK: - Properties

    private let deviceMetadata: DeviceMetadata

    // MARK: - Initialization

    internal init(deviceMetadata: DeviceMetadata = DeviceMetadata()) {
        self.deviceMetadata = deviceMetadata
    }

    // MARK: - Public API

    /// Returns a ``CapabilityProfile`` describing the current device.
    ///
    /// This is a synchronous, local-only call. No network request is made.
    public func current() -> CapabilityProfile {
        let memoryMb = deviceMetadata.totalMemoryMB ?? 0

        // Classify device into a tier
        let deviceClass = classifyDevice(memoryMb: memoryMb)

        // Determine available runtimes
        var runtimes = ["coreml"]
        #if arch(arm64)
        // MLX is available on Apple Silicon (arm64) devices
        runtimes.append("mlx")
        #endif

        // Determine accelerators
        var accelerators: [String] = ["cpu"]
        if deviceMetadata.gpuAvailable {
            accelerators.append("gpu")
            accelerators.append("neural_engine")
        }

        return CapabilityProfile(
            deviceClass: deviceClass,
            availableRuntimes: runtimes,
            memoryMb: memoryMb,
            storageMb: deviceMetadata.availableStorageMB,
            platform: deviceMetadata.platform,
            accelerators: accelerators
        )
    }

    // MARK: - Private

    private func classifyDevice(memoryMb: Int) -> DeviceClass {
        if memoryMb >= 8 * 1024 {
            return .flagship
        } else if memoryMb >= 6 * 1024 {
            return .high
        } else if memoryMb >= 4 * 1024 {
            return .mid
        } else {
            return .low
        }
    }
}

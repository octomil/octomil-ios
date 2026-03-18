//
//  DeviceInfo.swift
//  Octomil iOS SDK
//
//  Collects device hardware metadata and runtime constraints
//  for monitoring and training eligibility.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreTelephony)
import CoreTelephony
#endif

/// Collects and manages device information for Octomil platform.
///
/// Automatically gathers:
/// - Stable device identifier (IDFV)
/// - Hardware specs (CPU, memory, storage, GPU)
/// - System info (iOS version, model)
/// - Runtime constraints (battery, network)
/// - Locale and timezone
///
/// Example:
/// ```swift
/// let deviceInfo = DeviceMetadata()
/// let registrationData = deviceInfo.toRegistrationDict()
/// ```
public class DeviceMetadata {

    // MARK: - Properties

    /// Stable device identifier (IDFV - Identifier For Vendor)
    public var deviceId: String {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }

    // MARK: - Device Hardware

    /// Get device manufacturer (always "Apple" for iOS)
    public var manufacturer: String {
        return "Apple"
    }

    /// Get device model (e.g., "iPhone 15 Pro", "iPad Air")
    public var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        #if canImport(UIKit)
        return modelCode ?? UIDevice.current.model
        #else
        return modelCode ?? "Mac"
        #endif
    }

    /// Resolves this device's profile key using the ``DeviceProfileClient``.
    ///
    /// The server uses profile keys to select the optimal model format,
    /// quantization settings, and MNN runtime config for the device.
    /// When the server mapping is unavailable, falls back to a RAM-based
    /// tier classification (high/mid/low) with no hardcoded device IDs.
    ///
    /// - Parameter profileClient: The client that fetches and caches server profiles.
    /// - Returns: Device profile key (e.g. "iphone_15_pro", "high", "mid").
    public func resolveDeviceProfile(using profileClient: DeviceProfileClient) async -> String {
        let memoryMB = totalMemoryMB ?? 4096 // Conservative default if unknown
        return await profileClient.resolveProfile(machineId: model, totalMemoryMB: memoryMB)
    }

    /// RAM-only fallback profile classification when no ``DeviceProfileClient`` is available.
    ///
    /// Returns a generic tier string based on available RAM. No hardcoded device
    /// model identifiers are used.
    public var deviceProfile: String {
        let memoryMB = totalMemoryMB ?? 4096
        return DeviceRAMTier.classify(totalMemoryMB: memoryMB).rawValue
    }

    /// Get CPU architecture (arm64)
    public var cpuArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Check if Neural Engine (GPU) is available
    public var gpuAvailable: Bool {
        // iOS devices from A11 Bionic onward have Neural Engine
        if #available(iOS 11.0, *) {
            return true
        }
        return false
    }

    /// Get total physical memory in MB
    public var totalMemoryMB: Int? {
        return Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
    }

    /// Get available storage space in MB
    public var availableStorageMB: Int? {
        guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return Int(freeSize.int64Value / (1024 * 1024))
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Runtime Constraints

    /// Get current battery level (0-100)
    public var batteryLevel: Int? {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = false

        if level < 0 {
            return nil  // Battery level unknown
        }
        return Int(level * 100)
        #else
        return nil
        #endif
    }

    /// Get current network type (wifi, cellular, unknown)
    public var networkType: String {
        guard let reachability = try? Reachability() else {
            return "unknown"
        }

        switch reachability.connection {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .unavailable:
            return "offline"
        case .none:
            return "unknown"
        }
    }

    // MARK: - System Info

    /// Get iOS platform string
    public var platform: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    /// Get iOS version
    public var osVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// Get user's locale
    public var locale: String {
        return Locale.current.identifier
    }

    /// Get user's region
    public var region: String {
        return Locale.current.regionCode ?? "US"
    }

    /// Get user's timezone
    public var timezone: String {
        return TimeZone.current.identifier
    }

    // MARK: - Collection Methods

    /// Collect complete device hardware information
    public func collectDeviceInfo() -> [String: Any] {
        var info: [String: Any] = [
            "manufacturer": manufacturer,
            "model": model,
            "cpu_architecture": cpuArchitecture,
            "gpu_available": gpuAvailable
        ]

        if let memory = totalMemoryMB {
            info["total_memory_mb"] = memory
        }

        if let storage = availableStorageMB {
            info["available_storage_mb"] = storage
        }

        return info
    }

    /// Collect runtime metadata (battery, network)
    public func collectMetadata() -> [String: Any] {
        var metadata: [String: Any] = [
            "network_type": networkType
        ]

        if let battery = batteryLevel {
            metadata["battery_level"] = battery
        }

        return metadata
    }

    /// Collect ML capabilities
    public func collectCapabilities() -> [String: Any] {
        return [
            "cpu_architecture": cpuArchitecture,
            "gpu_available": gpuAvailable,
            "coreml": true,
            "neural_engine": gpuAvailable
        ]
    }

    /// Create registration payload for Octomil API
    public func toRegistrationDict() -> [String: Any] {
        return [
            "device_identifier": deviceId,
            "platform": platform,
            "os_version": osVersion,
            "device_info": collectDeviceInfo(),
            "locale": locale,
            "region": region,
            "timezone": timezone,
            "metadata": collectMetadata(),
            "capabilities": collectCapabilities()
        ]
    }

    /// Get updated metadata for heartbeat updates
    ///
    /// Call this periodically to send updated battery/network status.
    public func updateMetadata() -> [String: Any] {
        return collectMetadata()
    }
}

// MARK: - Reachability Helper

/// Simple reachability check for network type detection
private class Reachability {
    enum Connection {
        case unavailable
        case wifi
        case cellular
        case none
    }

    var connection: Connection {
        // This is a simplified implementation
        // In production, use Network framework or a proper Reachability library
        return .wifi  // Default assumption
    }
}

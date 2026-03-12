import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Monitors device state (battery, thermal, memory, low-power mode) in real time.
///
/// Uses `UIDevice` for battery state on iOS and `ProcessInfo` for thermal state
/// and low-power mode on all platforms. Emits state changes via an `AsyncStream`.
public actor DeviceStateMonitor {

    // MARK: - Types

    /// Snapshot of the current device state.
    public struct DeviceState: Sendable, Equatable {
        /// Battery level from 0.0 (empty) to 1.0 (full). -1.0 when unknown.
        public let batteryLevel: Float
        /// Current battery charging state.
        public let batteryState: BatteryState
        /// Current thermal pressure on the device.
        public let thermalState: ThermalState
        /// Approximate available memory in megabytes.
        public let availableMemoryMB: Int
        /// Whether the user has enabled Low Power Mode.
        public let isLowPowerMode: Bool

        public init(
            batteryLevel: Float,
            batteryState: BatteryState,
            thermalState: ThermalState,
            availableMemoryMB: Int,
            isLowPowerMode: Bool
        ) {
            self.batteryLevel = batteryLevel
            self.batteryState = batteryState
            self.thermalState = thermalState
            self.availableMemoryMB = availableMemoryMB
            self.isLowPowerMode = isLowPowerMode
        }
    }

    /// Battery charging state.
    public enum BatteryState: String, Sendable, Codable {
        case unknown
        case unplugged
        case charging
        case full
    }

    /// Device thermal state, mirroring `ProcessInfo.ThermalState`.
    public enum ThermalState: String, Sendable, Codable, Comparable {
        case nominal
        case fair
        case serious
        case critical

        private var order: Int {
            switch self {
            case .nominal: return 0
            case .fair: return 1
            case .serious: return 2
            case .critical: return 3
            }
        }

        public static func < (lhs: ThermalState, rhs: ThermalState) -> Bool {
            lhs.order < rhs.order
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "DeviceStateMonitor")
    private var isMonitoring = false
    private var _currentState: DeviceState
    private var continuation: AsyncStream<DeviceState>.Continuation?
    private var observerTokens: [NSObjectProtocol] = []
    private var pollingTask: Task<Void, Never>?

    /// Polling interval for state checks in seconds.
    private let pollingInterval: TimeInterval

    // MARK: - Public API

    /// Current device state snapshot.
    public var currentState: DeviceState {
        _currentState
    }

    /// Async stream that yields a new `DeviceState` whenever a meaningful change occurs.
    public var stateChanges: AsyncStream<DeviceState> {
        AsyncStream<DeviceState> { continuation in
            self.continuation = continuation
            continuation.yield(self._currentState)
        }
    }

    // MARK: - Initialization

    /// Creates a new device state monitor.
    /// - Parameter pollingInterval: How often to poll state that lacks notifications (default: 10s).
    public init(pollingInterval: TimeInterval = 10) {
        self.pollingInterval = pollingInterval
        self._currentState = DeviceState(
            batteryLevel: -1.0,
            batteryState: .unknown,
            thermalState: .nominal,
            availableMemoryMB: 0,
            isLowPowerMode: false
        )
    }

    /// Starts monitoring device state. Safe to call multiple times.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        #if os(iOS)
        enableBatteryMonitoring()
        #endif

        registerNotifications()
        refreshState()
        startPolling()

        logger.debug("DeviceStateMonitor started")
    }

    /// Stops monitoring and cleans up observers.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        pollingTask?.cancel()
        pollingTask = nil

        #if os(iOS)
        disableBatteryMonitoring()
        #endif

        removeNotifications()
        continuation?.finish()
        continuation = nil

        logger.debug("DeviceStateMonitor stopped")
    }

    // MARK: - Internal

    #if os(iOS)
    private func enableBatteryMonitoring() {
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }

    private func disableBatteryMonitoring() {
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }
    #endif

    private func registerNotifications() {
        let center = NotificationCenter.default

        // Thermal state changes
        let thermalToken = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshState() }
        }
        observerTokens.append(thermalToken)

        // Low Power Mode changes (macOS 12+ / iOS 9+)
        #if os(iOS)
        let powerToken = center.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshState() }
        }
        observerTokens.append(powerToken)
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            let powerToken = center.addObserver(
                forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshState() }
            }
            observerTokens.append(powerToken)
        }
        #endif

        #if os(iOS)
        // Battery level changes
        let batteryLevelToken = center.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshState() }
        }
        observerTokens.append(batteryLevelToken)

        // Battery state changes
        let batteryStateToken = center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshState() }
        }
        observerTokens.append(batteryStateToken)
        #endif
    }

    private func removeNotifications() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.pollingInterval ?? 10) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.refreshState()
            }
        }
    }

    /// Reads current device state from system APIs and emits if changed.
    private func refreshState() {
        let newState = readDeviceState()
        if newState != _currentState {
            _currentState = newState
            continuation?.yield(newState)
        }
    }

    /// Reads device state from platform APIs.
    private nonisolated func readDeviceState() -> DeviceState {
        let batteryLevel: Float
        let batteryState: BatteryState

        #if os(iOS)
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = mapBatteryState(UIDevice.current.batteryState)
        #else
        batteryLevel = 1.0   // Assume plugged in on macOS
        batteryState = .full
        #endif

        let thermalState = mapThermalState(ProcessInfo.processInfo.thermalState)
        let availableMemoryMB = readAvailableMemoryMB()
        let isLowPowerMode = readIsLowPowerMode()

        return DeviceState(
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            thermalState: thermalState,
            availableMemoryMB: availableMemoryMB,
            isLowPowerMode: isLowPowerMode
        )
    }

    #if os(iOS)
    private nonisolated func mapBatteryState(_ state: UIDevice.BatteryState) -> BatteryState {
        switch state {
        case .unknown:
            return .unknown
        case .unplugged:
            return .unplugged
        case .charging:
            return .charging
        case .full:
            return .full
        @unknown default:
            return .unknown
        }
    }
    #endif

    private nonisolated func mapThermalState(_ state: ProcessInfo.ThermalState) -> ThermalState {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }

    private nonisolated func readIsLowPowerMode() -> Bool {
        #if os(iOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        return false
        #else
        return false
        #endif
    }

    private nonisolated func readAvailableMemoryMB() -> Int {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // os_proc_available_memory() is available on iOS 13+ / tvOS 13+ / watchOS 6+
        let bytes = os_proc_available_memory()
        return Int(bytes / (1024 * 1024))
        #else
        // On macOS, os_proc_available_memory() is unavailable.
        // Use ProcessInfo physical memory as a rough upper bound.
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        return Int(totalBytes / (1024 * 1024))
        #endif
    }
}

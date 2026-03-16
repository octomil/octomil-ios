import Foundation

/// Configuration for device monitoring (heartbeats, health checks).
public struct MonitoringConfig: Sendable {
    /// Whether monitoring is enabled.
    public let enabled: Bool

    /// Interval between heartbeat reports in seconds.
    public let heartbeatInterval: TimeInterval

    public init(enabled: Bool = false, heartbeatInterval: TimeInterval = 300) {
        self.enabled = enabled
        self.heartbeatInterval = heartbeatInterval
    }

    public static let enabled = MonitoringConfig(enabled: true)
    public static let disabled = MonitoringConfig(enabled: false)
}

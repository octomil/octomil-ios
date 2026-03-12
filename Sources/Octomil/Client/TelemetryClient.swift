import Foundation
import os.log

/// Public telemetry facade for recording custom events.
///
/// Access via ``OctomilClient/telemetry``:
///
/// ```swift
/// client.telemetry.track(name: "user.action", attributes: [
///     "button": "checkout",
///     "latency_ms": "42"
/// ])
///
/// await client.telemetry.flush()
/// ```
///
/// Events are batched and sent through the same v2 OTLP pipeline
/// used by internal SDK telemetry.
public final class TelemetryClient: @unchecked Sendable {

    // MARK: - Properties

    private let logger: Logger

    /// Resolves the TelemetryQueue lazily so we pick up
    /// whichever queue was initialized by the SDK.
    private let queueProvider: () -> TelemetryQueue?

    // MARK: - Initialization

    internal init(queueProvider: @escaping () -> TelemetryQueue?) {
        self.queueProvider = queueProvider
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "TelemetryClient")
    }

    // MARK: - Public API

    /// Records a custom telemetry event.
    ///
    /// The event is buffered and sent to the server when the batch threshold
    /// is reached or on the next periodic flush.
    ///
    /// - Parameters:
    ///   - name: Event name (e.g. "user.action", "app.screen_view").
    ///   - attributes: Arbitrary key-value attributes attached to the event.
    public func track(name: String, attributes: [String: Any] = [:]) {
        guard let queue = queueProvider() else {
            logger.warning("Telemetry track('\(name)') called but no TelemetryQueue is initialized")
            return
        }

        var telemetryAttrs: [String: TelemetryValue] = [:]
        for (key, value) in attributes {
            telemetryAttrs[key] = coerceToTelemetryValue(value)
        }

        let event = TelemetryEvent(
            name: name,
            attributes: telemetryAttrs
        )
        queue.recordEvent(event)
    }

    /// Flushes all buffered telemetry events to the server immediately.
    ///
    /// This is useful before the app moves to background or on teardown.
    public func flush() async {
        guard let queue = queueProvider() else {
            return
        }
        await queue.flush()
    }

    // MARK: - Private

    private func coerceToTelemetryValue(_ value: Any) -> TelemetryValue {
        switch value {
        case let s as String:
            return .string(s)
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let d as Double:
            return .double(d)
        case let f as Float:
            return .double(Double(f))
        default:
            return .string(String(describing: value))
        }
    }
}

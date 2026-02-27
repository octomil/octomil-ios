import Foundation

// MARK: - V2 OTLP Envelope

/// Resource metadata identifying the SDK instance.
public struct TelemetryResource: Codable, Sendable {
    /// SDK identifier (always "ios").
    public let sdk: String
    /// SDK version string.
    public let sdkVersion: String
    /// Stable device identifier (IDFV).
    public let deviceId: String
    /// Platform identifier (always "ios").
    public let platform: String
    /// Organization identifier.
    public let orgId: String

    enum CodingKeys: String, CodingKey {
        case sdk
        case sdkVersion = "sdk_version"
        case deviceId = "device_id"
        case platform
        case orgId = "org_id"
    }

    public init(
        sdk: String = "ios",
        sdkVersion: String = OctomilVersion.current,
        deviceId: String,
        platform: String = "ios",
        orgId: String
    ) {
        self.sdk = sdk
        self.sdkVersion = sdkVersion
        self.deviceId = deviceId
        self.platform = platform
        self.orgId = orgId
    }
}

/// A single telemetry event in v2 OTLP format.
public struct TelemetryEvent: Codable, Sendable {
    /// Dot-notation event name (e.g. "inference.completed", "funnel.app_pair").
    public let name: String
    /// ISO 8601 timestamp.
    public let timestamp: String
    /// Flat attribute map with dot-notation keys.
    public let attributes: [String: TelemetryValue]
    /// Optional distributed trace identifier.
    public let traceId: String?
    /// Optional span identifier within a trace.
    public let spanId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case timestamp
        case attributes
        case traceId = "trace_id"
        case spanId = "span_id"
    }

    public init(
        name: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        attributes: [String: TelemetryValue],
        traceId: String? = nil,
        spanId: String? = nil
    ) {
        self.name = name
        self.timestamp = timestamp
        self.attributes = attributes
        self.traceId = traceId
        self.spanId = spanId
    }
}

/// A type-safe telemetry attribute value.
public enum TelemetryValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "TelemetryValue must be string, int, double, or bool"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }

    /// Convenience accessor for string values.
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Convenience accessor for double values.
    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }

    /// Convenience accessor for int values.
    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    /// Convenience accessor for bool values.
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

/// V2 OTLP envelope sent to `POST /api/v2/telemetry/events`.
public struct TelemetryEnvelope: Codable, Sendable {
    /// Resource metadata for this SDK instance.
    public let resource: TelemetryResource
    /// Batch of telemetry events.
    public let events: [TelemetryEvent]

    public init(resource: TelemetryResource, events: [TelemetryEvent]) {
        self.resource = resource
        self.events = events
    }
}

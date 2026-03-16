import Foundation

// MARK: - OTLP/JSON Types

/// OTLP ExportLogsServiceRequest — the top-level payload sent to
/// `POST /api/v2/telemetry/events`.
public struct ExportLogsServiceRequest: Codable, Sendable {
    public let resourceLogs: [ResourceLogs]

    enum CodingKeys: String, CodingKey {
        case resourceLogs = "resourceLogs"
    }

    public init(resourceLogs: [ResourceLogs]) {
        self.resourceLogs = resourceLogs
    }
}

/// A set of log records from a single resource.
public struct ResourceLogs: Codable, Sendable {
    public let resource: OtlpResource
    public let scopeLogs: [ScopeLogs]

    enum CodingKeys: String, CodingKey {
        case resource
        case scopeLogs = "scopeLogs"
    }

    public init(resource: OtlpResource, scopeLogs: [ScopeLogs]) {
        self.resource = resource
        self.scopeLogs = scopeLogs
    }
}

/// OTLP Resource identifying the SDK instance.
public struct OtlpResource: Codable, Sendable {
    public let attributes: [KeyValue]

    public init(attributes: [KeyValue]) {
        self.attributes = attributes
    }

    /// Convenience: build resource attributes from SDK metadata.
    public static func fromSDK(
        sdk: String = "ios",
        sdkVersion: String = OctomilVersion.current,
        deviceId: String,
        platform: String = "ios",
        orgId: String,
        installId: String? = nil
    ) -> OtlpResource {
        var attrs = [
            KeyValue(key: "sdk", value: .stringValue(sdk)),
            KeyValue(key: "sdk.version", value: .stringValue(sdkVersion)),
            KeyValue(key: "device.id", value: .stringValue(deviceId)),
            KeyValue(key: "platform", value: .stringValue(platform)),
            KeyValue(key: "org.id", value: .stringValue(orgId)),
        ]
        if let installId {
            attrs.append(KeyValue(key: OTLPResourceAttribute.octomilInstallId, value: .stringValue(installId)))
        }
        return OtlpResource(attributes: attrs)
    }
}

/// A group of log records scoped by an instrumentation library.
public struct ScopeLogs: Codable, Sendable {
    public let scope: InstrumentationScope
    public let logRecords: [LogRecord]

    enum CodingKeys: String, CodingKey {
        case scope
        case logRecords = "logRecords"
    }

    public init(scope: InstrumentationScope, logRecords: [LogRecord]) {
        self.scope = scope
        self.logRecords = logRecords
    }
}

/// Identifies the instrumentation library that produced the logs.
public struct InstrumentationScope: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String = "ai.octomil.sdk", version: String = OctomilVersion.current) {
        self.name = name
        self.version = version
    }
}

/// A single OTLP log record.
public struct LogRecord: Codable, Sendable {
    public let timeUnixNano: String
    public let severityNumber: Int
    public let severityText: String
    public let body: AnyValue
    public let attributes: [KeyValue]
    public let traceId: String?
    public let spanId: String?

    enum CodingKeys: String, CodingKey {
        case timeUnixNano = "timeUnixNano"
        case severityNumber = "severityNumber"
        case severityText = "severityText"
        case body
        case attributes
        case traceId = "traceId"
        case spanId = "spanId"
    }

    public init(
        timeUnixNano: String,
        severityNumber: Int = 9,
        severityText: String = "INFO",
        body: AnyValue,
        attributes: [KeyValue] = [],
        traceId: String? = nil,
        spanId: String? = nil
    ) {
        self.timeUnixNano = timeUnixNano
        self.severityNumber = severityNumber
        self.severityText = severityText
        self.body = body
        self.attributes = attributes
        self.traceId = traceId
        self.spanId = spanId
    }
}

/// An OTLP key-value attribute pair.
public struct KeyValue: Codable, Sendable, Equatable {
    public let key: String
    public let value: AnyValue

    public init(key: String, value: AnyValue) {
        self.key = key
        self.value = value
    }
}

/// OTLP AnyValue — a discriminated union encoded with typed keys
/// (e.g. `{"stringValue": "hello"}`, `{"intValue": "42"}`).
public enum AnyValue: Sendable, Equatable {
    case stringValue(String)
    case intValue(Int64)
    case doubleValue(Double)
    case boolValue(Bool)
    case arrayValue([AnyValue])
    case kvlistValue([KeyValue])

    // MARK: - Convenience factories from TelemetryValue

    static func from(_ tv: TelemetryValue) -> AnyValue {
        switch tv {
        case .string(let v): return .stringValue(v)
        case .int(let v): return .intValue(Int64(v))
        case .double(let v): return .doubleValue(v)
        case .bool(let v): return .boolValue(v)
        }
    }
}

extension AnyValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case stringValue, intValue, doubleValue, boolValue, arrayValue, kvlistValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try container.decodeIfPresent(String.self, forKey: .stringValue) {
            self = .stringValue(v)
        } else if let v = try container.decodeIfPresent(String.self, forKey: .intValue) {
            self = .intValue(Int64(v) ?? 0)
        } else if let v = try container.decodeIfPresent(Double.self, forKey: .doubleValue) {
            self = .doubleValue(v)
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .boolValue) {
            self = .boolValue(v)
        } else if let v = try container.decodeIfPresent([AnyValue].self, forKey: .arrayValue) {
            self = .arrayValue(v)
        } else if let v = try container.decodeIfPresent([KeyValue].self, forKey: .kvlistValue) {
            self = .kvlistValue(v)
        } else {
            self = .stringValue("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stringValue(let v):
            try container.encode(v, forKey: .stringValue)
        case .intValue(let v):
            try container.encode(String(v), forKey: .intValue)
        case .doubleValue(let v):
            try container.encode(v, forKey: .doubleValue)
        case .boolValue(let v):
            try container.encode(v, forKey: .boolValue)
        case .arrayValue(let v):
            try container.encode(v, forKey: .arrayValue)
        case .kvlistValue(let v):
            try container.encode(v, forKey: .kvlistValue)
        }
    }
}

// MARK: - Legacy TelemetryEvent (internal buffer format)

/// A single telemetry event in the internal buffer format.
/// Converted to OTLP ``LogRecord`` at flush time.
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

    /// Convert to an OTLP ``LogRecord``.
    func toLogRecord() -> LogRecord {
        let isoFormatter = ISO8601DateFormatter()
        let date = isoFormatter.date(from: timestamp) ?? Date()
        let nanos = UInt64(date.timeIntervalSince1970 * 1_000_000_000)

        var kvAttributes = attributes.map { key, value in
            KeyValue(key: key, value: AnyValue.from(value))
        }
        kvAttributes.sort { $0.key < $1.key }

        return LogRecord(
            timeUnixNano: String(nanos),
            severityNumber: 9,
            severityText: "INFO",
            body: .stringValue(name),
            attributes: kvAttributes,
            traceId: traceId,
            spanId: spanId
        )
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

// MARK: - Legacy Compatibility Aliases

/// Resource metadata identifying the SDK instance.
/// Deprecated: Use ``OtlpResource`` with OTLP attributes instead.
public struct TelemetryResource: Codable, Sendable {
    public let sdk: String
    public let sdkVersion: String
    public let deviceId: String
    public let platform: String
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

    /// Convert to an ``OtlpResource``.
    public func toOtlpResource() -> OtlpResource {
        OtlpResource.fromSDK(
            sdk: sdk,
            sdkVersion: sdkVersion,
            deviceId: deviceId,
            platform: platform,
            orgId: orgId,
            installId: InstallId.getOrCreate()
        )
    }
}

/// Legacy envelope — kept for backward compatibility with OctomilClient inline telemetry.
/// The canonical wire format is now ``ExportLogsServiceRequest``.
public struct TelemetryEnvelope: Codable, Sendable {
    public let resource: TelemetryResource
    public let events: [TelemetryEvent]

    public init(resource: TelemetryResource, events: [TelemetryEvent]) {
        self.resource = resource
        self.events = events
    }

    /// Convert to an OTLP ``ExportLogsServiceRequest``.
    public func toOTLP() -> ExportLogsServiceRequest {
        let logRecords = events.map { $0.toLogRecord() }
        return ExportLogsServiceRequest(
            resourceLogs: [
                ResourceLogs(
                    resource: resource.toOtlpResource(),
                    scopeLogs: [
                        ScopeLogs(
                            scope: InstrumentationScope(),
                            logRecords: logRecords
                        ),
                    ]
                ),
            ]
        )
    }
}

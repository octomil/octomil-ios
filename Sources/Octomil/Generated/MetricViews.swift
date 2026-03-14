// Auto-generated metric view constants.

public struct MetricView: Sendable {
    public let name: String
    public let instrument: String
    public let unit: String
    public let sourceSpan: String
}

public enum MetricViews {
    public static let octomilResponseDuration = "octomil.response.duration"
    public static let octomilResponseTtft = "octomil.response.ttft"
    public static let octomilResponseTokensPerSecond = "octomil.response.tokens_per_second"
    public static let octomilModelLoadDuration = "octomil.model.load.duration"
    public static let octomilModelLoadFailureRate = "octomil.model.load.failure_rate"
    public static let octomilFallbackRate = "octomil.fallback.rate"
    public static let octomilHeartbeatFreshness = "octomil.heartbeat.freshness"
    public static let octomilToolExecuteDuration = "octomil.tool.execute.duration"

    public static let allMetricViews = [
        MetricView(name: "octomil.response.duration", instrument: "histogram", unit: "ms", sourceSpan: "octomil.response"),
        MetricView(name: "octomil.response.ttft", instrument: "histogram", unit: "ms", sourceSpan: "octomil.response"),
        MetricView(name: "octomil.response.tokens_per_second", instrument: "histogram", unit: "{tokens}/s", sourceSpan: "octomil.response"),
        MetricView(name: "octomil.model.load.duration", instrument: "histogram", unit: "ms", sourceSpan: "octomil.model.load"),
        MetricView(name: "octomil.model.load.failure_rate", instrument: "counter", unit: "{failures}", sourceSpan: "octomil.model.load"),
        MetricView(name: "octomil.fallback.rate", instrument: "counter", unit: "{fallbacks}", sourceSpan: "octomil.response"),
        MetricView(name: "octomil.heartbeat.freshness", instrument: "gauge", unit: "s", sourceSpan: "octomil.control.heartbeat"),
        MetricView(name: "octomil.tool.execute.duration", instrument: "histogram", unit: "ms", sourceSpan: "octomil.tool.execute"),
    ]
}

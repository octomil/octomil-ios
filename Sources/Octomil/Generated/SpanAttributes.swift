// Auto-generated span attribute key constants.

public enum SpanAttribute {
    public static let modelId = "model.id"
    public static let modelVersion = "model.version"
    public static let runtimeExecutor = "runtime.executor"
    public static let requestMode = "request.mode"
    public static let locality = "locality"
    public static let streaming = "streaming"
    public static let routePolicy = "route.policy"
    public static let routeDecision = "route.decision"
    public static let deviceClass = "device.class"
    public static let fallbackReason = "fallback.reason"
    public static let errorType = "error.type"
    public static let modelSourceFormat = "model.source_format"
    public static let modelSizeBytes = "model.size_bytes"
    public static let toolName = "tool.name"
    public static let toolRound = "tool.round"
    public static let fallbackProvider = "fallback.provider"
    public static let assignmentCount = "assignment_count"
    public static let heartbeatSequence = "heartbeat.sequence"
    public static let rolloutId = "rollout.id"
    public static let modelsSynced = "models_synced"

    public static let spanRequiredAttributes: [String: [String]] = [
        "octomil.response": ["model.id", "model.version", "runtime.executor", "request.mode", "locality", "streaming"],
        "octomil.model.load": ["model.id", "model.version", "runtime.executor"],
        "octomil.tool.execute": ["tool.name", "tool.round"],
        "octomil.fallback.cloud": ["model.id", "fallback.reason"],
        "octomil.control.refresh": [],
        "octomil.control.heartbeat": ["heartbeat.sequence"],
        "octomil.rollout.sync": ["rollout.id"],
    ]
}

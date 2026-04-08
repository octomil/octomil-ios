import Foundation

// MARK: - Telemetry & Adaptation

extension APIClient {

    /// Sends a batch of telemetry events to the v2 OTLP endpoint.
    /// - Parameter envelope: The v2 OTLP telemetry envelope (legacy format, converted to OTLP on send).
    public func reportTelemetryEvents(_ envelope: TelemetryEnvelope) async throws {
        try await reportTelemetryOTLP(envelope.toOTLP())
    }

    /// Sends an OTLP ExportLogsServiceRequest to the v2 telemetry endpoint.
    /// - Parameter request: The OTLP payload.
    public func reportTelemetryOTLP(_ request: ExportLogsServiceRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v2/telemetry/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: APIEmptyResponse = try await performRequest(urlRequest)
    }

    /// Reports current device state and gets a compute recommendation from the server.
    ///
    /// This allows the server to coordinate adaptation across the fleet, e.g.
    /// recommending specific compute strategies based on global model performance data.
    ///
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - modelId: Model identifier being used for inference.
    ///   - batteryLevel: Current battery level (0.0-1.0).
    ///   - thermalState: Current thermal state string (nominal/fair/serious/critical).
    ///   - currentFormat: Current model format (e.g. "coreml").
    ///   - currentExecutor: Current compute executor (e.g. "all", "cpuAndGPU", "cpuOnly").
    /// - Returns: Server-side adaptation recommendation.
    public func getAdaptationRecommendation(
        deviceId: String,
        modelId: String,
        batteryLevel: Float,
        thermalState: String,
        currentFormat: String,
        currentExecutor: String
    ) async throws -> AdaptationRecommendation {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/adapt")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: Any] = [
            "battery_level": batteryLevel,
            "thermal_state": thermalState,
            "current_format": currentFormat,
            "current_executor": currentExecutor,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performRequest(urlRequest)
    }

    /// Reports a model format/executor failure and requests a fallback.
    ///
    /// When a particular model format or executor fails on-device, this endpoint
    /// tells the server so it can track failure rates and recommend an alternative.
    ///
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - modelId: Model identifier.
    ///   - version: Model version string.
    ///   - failedFormat: The format that failed (e.g. "coreml").
    ///   - failedExecutor: The executor that failed (e.g. "all").
    ///   - errorMessage: Error message from the failure.
    /// - Returns: Server-side fallback recommendation with alternative format/executor.
    public func getFallback(
        deviceId: String,
        modelId: String,
        version: String,
        failedFormat: String,
        failedExecutor: String,
        errorMessage: String
    ) async throws -> FallbackRecommendation {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/fallback")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: String] = [
            "version": version,
            "failed_format": failedFormat,
            "failed_executor": failedExecutor,
            "error_message": errorMessage,
        ]
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }
}

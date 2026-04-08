import Foundation

// MARK: - Training, Rounds & Experiments

extension APIClient {

    /// Lists training rounds.
    /// - Parameters:
    ///   - modelId: Model identifier to filter by.
    ///   - state: Round state to filter by (e.g., "waiting_for_updates").
    ///   - deviceId: Device identifier to filter by.
    /// - Returns: List of round assignments.
    public func listRounds(
        modelId: String,
        state: String? = nil,
        deviceId: String? = nil
    ) async throws -> [RoundAssignment] {
        var queryItems = [URLQueryItem(name: "model_id", value: modelId)]
        if let state = state {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        if let deviceId = deviceId {
            queryItems.append(URLQueryItem(name: "device_id", value: deviceId))
        }

        var components = URLComponents(
            url: serverURL.appendingPathComponent("api/v1/training/rounds"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets a specific training round.
    /// - Parameter roundId: Round identifier.
    /// - Returns: Round assignment details.
    public func getRound(roundId: String) async throws -> RoundAssignment {
        let url = serverURL.appendingPathComponent("api/v1/training/rounds/\(roundId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Submits gradients for a training round.
    /// - Parameters:
    ///   - experimentId: Experiment or round identifier.
    ///   - request: Gradient update request.
    /// - Returns: Gradient update response.
    public func submitGradients(
        experimentId: String,
        request: GradientUpdateRequest
    ) async throws -> GradientUpdateResponse {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)/gradients")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    /// Uploads weight updates to the server.
    /// - Parameter update: Weight update to upload.
    public func uploadWeights(_ update: WeightUpdate) async throws {
        let url = serverURL.appendingPathComponent("api/v1/training/weights")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(update)

        let _: APIEmptyResponse = try await performRequest(urlRequest)
    }

    /// Tracks a metric on the server.
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - event: Event to track.
    public func trackMetric(experimentId: String, event: TrackingEvent) async throws {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(event)

        let _: APIEmptyResponse = try await performRequest(urlRequest)
    }

    /// Fetches all active experiments.
    public func getActiveExperiments() async throws -> [Experiment] {
        let url = serverURL.appendingPathComponent("api/v1/experiments")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Fetches config for a specific experiment.
    public func getExperimentConfig(experimentId: String) async throws -> Experiment {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }
}

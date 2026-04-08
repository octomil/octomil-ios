import Foundation

// MARK: - Pairing Endpoints (unauthenticated — the pairing code is the secret)

extension APIClient {

    /// Poll pairing session status.
    /// - Parameter code: Pairing code from QR scan.
    /// - Returns: Current pairing session state.
    public func getPairingSession(code: String) async throws -> PairingSession {
        let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        return try await performUnauthenticatedRequest(urlRequest)
    }

    /// Connect device to a pairing session.
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - deviceId: Client-generated device UUID.
    ///   - platform: Device platform (e.g. "ios").
    ///   - deviceName: Human-readable device name.
    ///   - chipFamily: SoC family (e.g. "A17 Pro").
    ///   - ramGB: Total RAM in gigabytes.
    ///   - osVersion: OS version string.
    ///   - npuAvailable: Whether NPU is available.
    ///   - gpuAvailable: Whether GPU is available for ML.
    /// - Returns: Updated pairing session.
    public func connectToPairing(
        code: String,
        deviceId: String,
        platform: String,
        deviceName: String,
        chipFamily: String?,
        ramGB: Double?,
        osVersion: String?,
        npuAvailable: Bool?,
        gpuAvailable: Bool?,
        locale: String? = nil,
        region: String? = nil,
        timezone: String? = nil
    ) async throws -> PairingSession {
        let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)/connect")

        var body: [String: Any] = [
            "device_id": deviceId,
            "platform": platform,
            "device_name": deviceName,
        ]
        if let chipFamily = chipFamily { body["chip_family"] = chipFamily }
        if let ramGB = ramGB { body["ram_gb"] = ramGB }
        if let osVersion = osVersion { body["os_version"] = osVersion }
        if let npuAvailable = npuAvailable { body["npu_available"] = npuAvailable }
        if let gpuAvailable = gpuAvailable { body["gpu_available"] = gpuAvailable }
        if let locale = locale { body["locale"] = locale }
        if let region = region { body["region"] = region }
        if let timezone = timezone { body["timezone"] = timezone }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performUnauthenticatedRequest(urlRequest)
    }

    /// Submit benchmark results for a pairing session.
    /// - Parameters:
    ///   - code: Pairing code.
    ///   - report: Benchmark report to submit.
    public func submitPairingBenchmark(code: String, report: BenchmarkReport) async throws {
        let url = serverURL.appendingPathComponent("api/v1/deploy/pair/\(code)/benchmark")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.httpBody = try jsonEncoder.encode(report)

        let _: PairingBenchmarkResponse = try await performUnauthenticatedRequest(urlRequest)
    }
}

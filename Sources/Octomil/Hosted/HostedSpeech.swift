import Foundation

/// Result of a hosted ``HostedSpeech.create(...)`` call.
public struct HostedSpeechResponse: Sendable {
    public let audioData: Data
    public let contentType: String
    public let provider: String?
    public let model: String?
    public let latencyMs: Double?
    public let billedUnits: Int?
    public let unitKind: String?

    public init(
        audioData: Data,
        contentType: String,
        provider: String? = nil,
        model: String? = nil,
        latencyMs: Double? = nil,
        billedUnits: Int? = nil,
        unitKind: String? = nil
    ) {
        self.audioData = audioData
        self.contentType = contentType
        self.provider = provider
        self.model = model
        self.latencyMs = latencyMs
        self.billedUnits = billedUnits
        self.unitKind = unitKind
    }

    /// Write the audio bytes to ``url``.
    public func write(to url: URL) throws {
        try audioData.write(to: url)
    }
}

public enum HostedSpeechError: Error, LocalizedError {
    case invalidInput(String)
    case requestFailed(status: Int, body: String)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .requestFailed(let status, let body):
            return "Hosted speech request failed: HTTP \(status): \(body)"
        case .transport(let err):
            return "Transport error: \(err.localizedDescription)"
        }
    }
}

/// Hosted text-to-speech surface (mirrors `openai.audio.speech`).
public final class HostedSpeech: @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let urlSession: URLSession

    init(baseURL: URL, apiKey: String, urlSession: URLSession) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    /// Synthesize speech from text. Returns the raw audio bytes plus
    /// Octomil routing metadata surfaced via ``X-Octomil-*`` response
    /// headers.
    public func create(
        model: String,
        input: String,
        voice: String? = nil,
        responseFormat: String = "mp3",
        speed: Double = 1.0
    ) async throws -> HostedSpeechResponse {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HostedSpeechError.invalidInput("`input` must be a non-empty string.")
        }

        let url = baseURL.appendingPathComponent("audio/speech")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "input": input,
            "response_format": responseFormat,
            "speed": speed,
        ]
        if let voice {
            body["voice"] = voice
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await urlSession.data(for: request)
        } catch {
            throw HostedSpeechError.transport(error)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw HostedSpeechError.requestFailed(status: -1, body: "unknown response shape")
        }
        if http.statusCode >= 400 {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw HostedSpeechError.requestFailed(status: http.statusCode, body: preview)
        }

        let contentType =
            (http.value(forHTTPHeaderField: "Content-Type")
                ?? http.value(forHTTPHeaderField: "content-type"))
            ?? "application/octet-stream"

        return HostedSpeechResponse(
            audioData: data,
            contentType: contentType,
            provider: http.value(forHTTPHeaderField: "X-Octomil-Provider"),
            model: http.value(forHTTPHeaderField: "X-Octomil-Model") ?? model,
            latencyMs: http.value(forHTTPHeaderField: "X-Octomil-Latency-Ms").flatMap(Double.init),
            billedUnits: http.value(forHTTPHeaderField: "X-Octomil-Billed-Units").flatMap(Int.init),
            unitKind: http.value(forHTTPHeaderField: "X-Octomil-Unit-Kind")
        )
    }
}

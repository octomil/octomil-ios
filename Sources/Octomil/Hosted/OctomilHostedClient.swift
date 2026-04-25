import Foundation

/// Hosted Octomil client.
///
/// Lightweight HTTP client targeting `api.octomil.com`. Distinct from
/// ``OctomilClient`` (the local-runtime facade) so hosted callers do not
/// pay the cost of importing the runtime planner / engine registry.
///
/// ```swift
/// let client = OctomilHostedClient(apiKey: ProcessInfo.processInfo.environment["OCTOMIL_API_KEY"]!)
/// let response = try await client.audio.speech.create(
///     model: "tts-1",
///     input: "Hello world.",
///     voice: "alloy"
/// )
/// try response.write(to: URL(fileURLWithPath: "hello.mp3"))
/// ```
public final class OctomilHostedClient: @unchecked Sendable {

    /// Default base URL for the Octomil hosted API.
    public static let defaultBaseURL = URL(string: "https://api.octomil.com/v1")!

    public let baseURL: URL
    public let apiKey: String
    public let urlSession: URLSession

    private let _audio: HostedAudio

    public init(
        apiKey: String,
        baseURL: URL = OctomilHostedClient.defaultBaseURL,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
        self._audio = HostedAudio(baseURL: baseURL, apiKey: apiKey, urlSession: urlSession)
    }

    public var audio: HostedAudio { _audio }
}

/// Audio surface on ``OctomilHostedClient``.
public final class HostedAudio: @unchecked Sendable {
    public let speech: HostedSpeech

    init(baseURL: URL, apiKey: String, urlSession: URLSession) {
        self.speech = HostedSpeech(baseURL: baseURL, apiKey: apiKey, urlSession: urlSession)
    }
}

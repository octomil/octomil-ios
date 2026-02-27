import Foundation
import os.log

// MARK: - StreamToken

/// A single token received from the cloud streaming inference endpoint.
public struct StreamToken: Sendable, Equatable {
    /// The generated token text (empty on the final `done` event).
    public let token: String

    /// Whether this is the final event in the stream.
    public let done: Bool

    /// The inference provider (e.g. "ollama").
    public let provider: String?

    /// Total latency in milliseconds (present on the final event).
    public let latencyMs: Double?

    /// Server-assigned session identifier (present on the final event).
    public let sessionId: String?
}

// MARK: - CloudStreamingClient

/// Consumes SSE responses from `POST /api/v1/inference/stream` and
/// yields ``StreamToken`` values via an `AsyncThrowingStream`.
///
/// Usage:
/// ```swift
/// let client = CloudStreamingClient(
///     serverURL: URL(string: "https://api.octomil.com/api/v1")!,
///     apiKey: "your-key"
/// )
/// for try await token in client.streamInference(modelId: "phi-4-mini", input: "Hello") {
///     print(token.token, terminator: "")
/// }
/// ```
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public final class CloudStreamingClient: @unchecked Sendable {

    private let serverURL: URL
    private let apiKey: String
    private let session: URLSession
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "CloudStreaming")

    public init(serverURL: URL, apiKey: String, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Stream tokens from the cloud inference endpoint.
    ///
    /// - Parameters:
    ///   - modelId: Model identifier (e.g. `"phi-4-mini"`).
    ///   - input: A plain string prompt.
    ///   - parameters: Optional generation parameters.
    /// - Returns: An `AsyncThrowingStream` of ``StreamToken`` values.
    public func streamInference(
        modelId: String,
        input: String,
        parameters: [String: Any]? = nil
    ) -> AsyncThrowingStream<StreamToken, Error> {
        let body = buildPayload(modelId: modelId, inputData: input, messages: nil, parameters: parameters)
        return makeStream(body: body)
    }

    /// Stream tokens using chat-style messages.
    ///
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - messages: Chat messages (`[["role": "user", "content": "..."]]`).
    ///   - parameters: Optional generation parameters.
    /// - Returns: An `AsyncThrowingStream` of ``StreamToken`` values.
    public func streamInference(
        modelId: String,
        messages: [[String: String]],
        parameters: [String: Any]? = nil
    ) -> AsyncThrowingStream<StreamToken, Error> {
        let body = buildPayload(modelId: modelId, inputData: nil, messages: messages, parameters: parameters)
        return makeStream(body: body)
    }

    // MARK: - Private

    private func buildPayload(
        modelId: String,
        inputData: String?,
        messages: [[String: String]]?,
        parameters: [String: Any]?
    ) -> [String: Any] {
        var payload: [String: Any] = ["model_id": modelId]
        if let inputData = inputData {
            payload["input_data"] = inputData
        }
        if let messages = messages {
            payload["messages"] = messages
        }
        if let parameters = parameters, !parameters.isEmpty {
            payload["parameters"] = parameters
        }
        return payload
    }

    private func makeStream(body: [String: Any]) -> AsyncThrowingStream<StreamToken, Error> {
        let url = serverURL.appendingPathComponent("inference/stream")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let session = self.session
        let logger = self.logger

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.finish(
                            throwing: OctomilError.serverError(
                                statusCode: code,
                                message: "Cloud streaming inference failed"
                            )
                        )
                        return
                    }

                    for try await line in bytes.lines {
                        if let token = Self.parseSSELine(line) {
                            continuation.yield(token)
                        }
                    }

                    continuation.finish()
                } catch {
                    logger.warning("Cloud streaming failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Parse a single SSE line into a ``StreamToken``, or `nil`.
    static func parseSSELine(_ line: String) -> StreamToken? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }

        let dataStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !dataStr.isEmpty else { return nil }

        guard let data = dataStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return StreamToken(
            token: json["token"] as? String ?? "",
            done: json["done"] as? Bool ?? false,
            provider: json["provider"] as? String,
            latencyMs: json["latency_ms"] as? Double,
            sessionId: json["session_id"] as? String
        )
    }
}

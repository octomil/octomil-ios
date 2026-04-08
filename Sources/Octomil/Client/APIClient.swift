import Foundation
import os.log

/// HTTP client for communicating with the Octomil server API.
public actor APIClient {

    // MARK: - API Paths

    internal static let defaultVersionAlias = "latest"

    // MARK: - Properties

    internal let serverURL: URL
    internal let configuration: OctomilConfiguration
    internal let session: URLSession
    internal let jsonDecoder: JSONDecoder
    internal let jsonEncoder: JSONEncoder
    internal let logger: Logger
    private let pinningDelegate: CertificatePinningDelegate?

    private var deviceToken: String?

    // MARK: - Initialization

    /// Creates a new API client.
    /// - Parameters:
    ///   - serverURL: The base URL of the Octomil server.
    ///   - configuration: SDK configuration.
    ///   - initialToken: Optional device token set synchronously at construction to avoid race conditions.
    public init(
        serverURL: URL,
        configuration: OctomilConfiguration,
        initialToken: String? = nil
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.deviceToken = initialToken
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "APIClient")

        // Configure URL session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.downloadTimeout
        sessionConfig.waitsForConnectivity = true
        if configuration.pinnedCertificateHashes.isEmpty {
            self.pinningDelegate = nil
            self.session = URLSession(configuration: sessionConfig)
        } else {
            let delegate = CertificatePinningDelegate(pinnedHashes: configuration.pinnedCertificateHashes)
            self.pinningDelegate = delegate
            self.session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        }

        // Configure JSON decoder
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601

        // Configure JSON encoder
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    /// Creates an API client with an injected URL session configuration (for testing).
    internal init(
        serverURL: URL,
        configuration: OctomilConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "APIClient")

        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.downloadTimeout
        self.session = URLSession(configuration: sessionConfiguration)
        self.pinningDelegate = nil

        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601

        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Token Management

    /// Sets the short-lived device access token for authenticated requests.
    public func setDeviceToken(_ token: String) {
        self.deviceToken = token
    }

    /// Gets the current device token.
    public func getDeviceToken() -> String? {
        return deviceToken
    }

    // MARK: - Generic JSON Helpers

    /// Sends a POST request with a JSON body and decodes the response.
    /// - Parameters:
    ///   - path: Relative API path (e.g. "api/v1/federations/{id}/analytics/descriptive").
    ///   - body: Encodable request body.
    /// - Returns: Decoded response.
    public func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let url = serverURL.appendingPathComponent(path)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }

    /// Sends a GET request with optional query items and decodes the response.
    /// - Parameters:
    ///   - path: Relative API path.
    ///   - queryItems: Optional query parameters.
    /// - Returns: Decoded response.
    public func getJSON<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        var components = URLComponents(
            url: serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    // MARK: - Download

    /// Downloads data from a URL, buffering the entire response in memory.
    /// - Parameter url: URL to download from.
    /// - Returns: Downloaded data.
    public func downloadData(from url: URL) async throws -> Data {
        if configuration.enableLogging {
            logger.debug("Downloading from: \(url.absoluteString)")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OctomilError.unknown(underlying: nil)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw OctomilError.downloadFailed(reason: "HTTP \(httpResponse.statusCode)")
                }

                return data
            } catch let error as OctomilError {
                throw error
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    // Exponential backoff
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw OctomilError.downloadFailed(reason: lastError?.localizedDescription ?? "Unknown error")
    }

    /// Downloads a file using streaming I/O, writing data incrementally to disk.
    ///
    /// Unlike ``downloadData(from:)`` this never holds the full file in memory.
    /// Progress is reported as bytes accumulate.
    ///
    /// - Parameters:
    ///   - url: URL to download from.
    ///   - destination: Local file URL to write the downloaded data to.
    ///   - expectedBytes: Expected total size in bytes (used when the server omits Content-Length).
    ///   - progress: Closure called as data arrives with `(bytesWritten, totalBytes)`.
    ///               `totalBytes` is -1 when the size is unknown.
    public func downloadFile(
        from url: URL,
        to destination: URL,
        expectedBytes: Int64 = -1,
        progress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        if configuration.enableLogging {
            logger.debug("Streaming download from: \(url.absoluteString)")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (asyncBytes, response) = try await session.bytes(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OctomilError.unknown(underlying: nil)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw OctomilError.downloadFailed(reason: "HTTP \(httpResponse.statusCode)")
                }

                let contentLength = httpResponse.expectedContentLength  // -1 if unknown
                let totalBytes: Int64 = if contentLength > 0 {
                    contentLength
                } else if expectedBytes > 0 {
                    expectedBytes
                } else {
                    -1
                }

                // Open file handle for incremental writes
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let fileHandle = try FileHandle(forWritingTo: destination)
                defer { try? fileHandle.close() }

                var bytesWritten: Int64 = 0
                // 256 KB write buffer — balances syscall overhead vs memory use
                let bufferSize = 256 * 1024
                var buffer = Data()
                buffer.reserveCapacity(bufferSize)

                for try await byte in asyncBytes {
                    buffer.append(byte)

                    if buffer.count >= bufferSize {
                        fileHandle.write(buffer)
                        bytesWritten += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                        progress(bytesWritten, totalBytes)
                    }
                }

                // Flush remaining bytes
                if !buffer.isEmpty {
                    fileHandle.write(buffer)
                    bytesWritten += Int64(buffer.count)
                    progress(bytesWritten, totalBytes)
                }

                return
            } catch let error as OctomilError {
                throw error
            } catch {
                // Clean up partial file on retry
                try? FileManager.default.removeItem(at: destination)
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw OctomilError.downloadFailed(reason: lastError?.localizedDescription ?? "Unknown error")
    }

    // MARK: - Internal Request Helpers

    internal func configureHeaders(_ request: inout URLRequest) throws {
        guard let bearer = deviceToken, !bearer.isEmpty else {
            throw OctomilError.authenticationFailed(reason: "Missing device access token")
        }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("octomil-ios/1.0", forHTTPHeaderField: "User-Agent")
    }

    // swiftlint:disable:next cyclomatic_complexity
    internal func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        if configuration.enableLogging {
            logger.debug("Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OctomilError.unknown(underlying: nil)
                }

                if configuration.enableLogging {
                    logger.debug("Response: \(httpResponse.statusCode)")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw self.mapErrorResponse(data: data, statusCode: httpResponse.statusCode)
                }

                // Handle empty responses
                if T.self == APIEmptyResponse.self, data.isEmpty || data == Data("null".utf8) {
                    guard let emptyResult = APIEmptyResponse() as? T else {
                        throw OctomilError.decodingError(underlying: "Failed to cast APIEmptyResponse")
                    }
                    return emptyResult
                }

                do {
                    return try jsonDecoder.decode(T.self, from: data)
                } catch {
                    throw OctomilError.decodingError(underlying: error.localizedDescription)
                }

            } catch let error as OctomilError {
                // Don't retry Octomil errors
                throw error
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw OctomilError.networkUnavailable
                case .timedOut:
                    throw OctomilError.requestTimeout
                case .cancelled:
                    throw OctomilError.cancelled
                default:
                    lastError = error
                    retries += 1
                    if retries < configuration.maxRetryAttempts {
                        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                    }
                }
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw OctomilError.unknown(underlying: lastError)
    }

    /// Performs an HTTP request that does not require authentication.
    /// Used for pairing endpoints where the pairing code serves as the secret.
    internal func performUnauthenticatedRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        if configuration.enableLogging {
            logger.debug("Request (unauth): \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctomilError.unknown(underlying: nil)
        }

        if configuration.enableLogging {
            logger.debug("Response: \(httpResponse.statusCode)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw self.mapErrorResponse(data: data, statusCode: httpResponse.statusCode)
        }

        // Handle empty responses
        if T.self == PairingBenchmarkResponse.self, data.isEmpty || data == Data("null".utf8) {
            guard let emptyResult = PairingBenchmarkResponse() as? T else {
                throw OctomilError.decodingError(underlying: "Failed to cast PairingBenchmarkResponse")
            }
            return emptyResult
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw OctomilError.decodingError(underlying: error.localizedDescription)
        }
    }

    /// Maps an error HTTP response to an ``OctomilError``.
    ///
    /// If the response body contains a contract `code` field, use ``ErrorCode``
    /// to produce a precise error. Otherwise fall back to HTTP status mapping.
    private func mapErrorResponse(data: Data, statusCode: Int) -> OctomilError {
        let parsed = try? jsonDecoder.decode(APIErrorResponse.self, from: data)
        let message = parsed?.displayMessage ?? String(data: data, encoding: .utf8) ?? "Unknown error"

        // Prefer the contract error code when present.
        if let codeString = parsed?.code, let errorCode = ErrorCode(rawValue: codeString) {
            return OctomilError.from(errorCode: errorCode, message: message)
        }

        // Fall back to HTTP status code mapping when `code` is absent.
        switch statusCode {
        case 400:
            return .invalidInput(reason: message)
        case 401:
            return .authenticationFailed(reason: message)
        case 403:
            return .forbidden(reason: message)
        case 404:
            return .serverError(statusCode: 404, message: message)
        case 429:
            return .rateLimited(retryAfter: nil)
        case 500...599:
            return .serverError(statusCode: statusCode, message: message)
        default:
            return .serverError(statusCode: statusCode, message: message)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let errorResponse = try? jsonDecoder.decode(APIErrorResponse.self, from: data) {
            return errorResponse.displayMessage
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Empty Response

/// Sentinel type for API endpoints that return no meaningful body.
/// Named to avoid collisions with other EmptyResponse types in the module.
internal struct APIEmptyResponse: Decodable {}

// MARK: - Pairing Benchmark Response

/// Empty response from the benchmark submission endpoint.
/// The server may return an empty body or a simple acknowledgment.
internal struct PairingBenchmarkResponse: Decodable {
    init() {}
}

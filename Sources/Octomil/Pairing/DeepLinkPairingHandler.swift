import Foundation
import os.log

/// Handles the end-to-end pairing flow triggered by an `octomil://pair` deep link.
///
/// This actor bridges ``DeepLinkHandler`` (URL parsing) with ``PairingManager``
/// (server communication and model download). It provides a single-call API for
/// consuming apps to handle the deep link pairing flow.
///
/// ## Usage
///
/// ```swift
/// let handler = DeepLinkPairingHandler(
///     defaultServerURL: URL(string: "https://api.octomil.com")!
/// )
///
/// // In your onOpenURL handler:
/// if let action = DeepLinkHandler.parse(url: url) {
///     let result = await handler.handle(action: action)
///     switch result {
///     case .success(let deployResult):
///         print("Paired! Model at: \(deployResult.persistedModelURL)")
///     case .failure(let error):
///         print("Pairing failed: \(error)")
///     }
/// }
/// ```
public actor DeepLinkPairingHandler {

    // MARK: - Properties

    private let defaultServerURL: URL
    private let configuration: OctomilConfiguration
    private let logger: Logger

    // MARK: - Initialization

    /// Creates a new deep link pairing handler.
    ///
    /// - Parameters:
    ///   - defaultServerURL: The server URL to use when the deep link does not specify a host.
    ///   - configuration: SDK configuration passed to the underlying ``PairingManager``.
    public init(
        defaultServerURL: URL,
        configuration: OctomilConfiguration = .standard
    ) {
        self.defaultServerURL = defaultServerURL
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "DeepLinkPairingHandler")
    }

    // MARK: - Public API

    /// Handles a ``DeepLinkAction`` and executes the appropriate flow.
    ///
    /// For `.pair` actions, this runs the full pairing flow: connect, wait for
    /// deployment, and download the model.
    ///
    /// For `.unknown` actions, returns a failure with ``DeepLinkError/unrecognizedAction``.
    ///
    /// - Parameter action: The parsed deep link action.
    /// - Returns: A `Result` containing the ``DeploymentResult`` on success,
    ///   or a ``DeepLinkError`` on failure.
    public func handle(action: DeepLinkAction) async -> Result<DeploymentResult, DeepLinkError> {
        switch action {
        case .pair(let token, let host):
            return await executePairing(token: token, host: host)

        case .unknown(let url):
            if configuration.enableLogging {
                logger.warning("Unrecognized deep link: \(url.absoluteString)")
            }
            return .failure(.unrecognizedAction(url: url))
        }
    }

    /// Convenience method that parses a URL and handles it in one call.
    ///
    /// Returns `nil` if the URL does not use the `octomil` scheme.
    ///
    /// - Parameter url: The incoming URL.
    /// - Returns: A `Result` if the URL was an `octomil://` deep link, or `nil`.
    public func handleURL(_ url: URL) async -> Result<DeploymentResult, DeepLinkError>? {
        guard let action = DeepLinkHandler.parse(url: url) else {
            return nil
        }
        return await handle(action: action)
    }

    // MARK: - Private

    private func executePairing(token: String, host: String?) async -> Result<DeploymentResult, DeepLinkError> {
        let serverURL: URL
        if let host, let parsed = URL(string: host) {
            serverURL = parsed
        } else {
            serverURL = defaultServerURL
        }

        if configuration.enableLogging {
            logger.info("Starting deep link pairing: token=\(token), server=\(serverURL.absoluteString)")
        }

        let manager = PairingManager(serverURL: serverURL, configuration: configuration)

        do {
            let result = try await manager.pair(code: token)

            if configuration.enableLogging {
                logger.info("Deep link pairing complete: model at \(result.persistedModelURL.path)")
            }

            return .success(result)
        } catch let error as PairingError {
            return .failure(.pairingFailed(underlying: error))
        } catch {
            return .failure(.networkError(underlying: error))
        }
    }
}

// MARK: - Deep Link Error

/// Errors that can occur when handling an `octomil://` deep link.
public enum DeepLinkError: LocalizedError, Sendable {

    /// The deep link action is not recognized by the SDK.
    case unrecognizedAction(url: URL)

    /// The pairing flow failed.
    case pairingFailed(underlying: PairingError)

    /// A network or other transport error occurred.
    case networkError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedAction(let url):
            return "Unrecognized deep link action: \(url.absoluteString)"
        case .pairingFailed(let underlying):
            return "Pairing failed: \(underlying.localizedDescription)"
        case .networkError(let underlying):
            return "Network error during pairing: \(underlying.localizedDescription)"
        }
    }

    // Sendable conformance: Error is not Sendable, but we only store
    // PairingError (which is Sendable) in .pairingFailed, and in .networkError
    // we accept the risk since the error is immediately captured and read.
    // This is a known Swift concurrency limitation.
}

// Equatable for DeepLinkError (needed for testing convenience)
extension DeepLinkError: Equatable {
    public static func == (lhs: DeepLinkError, rhs: DeepLinkError) -> Bool {
        switch (lhs, rhs) {
        case (.unrecognizedAction(let lURL), .unrecognizedAction(let rURL)):
            return lURL == rURL
        case (.pairingFailed(let lErr), .pairingFailed(let rErr)):
            return lErr.localizedDescription == rErr.localizedDescription
        case (.networkError(let lErr), .networkError(let rErr)):
            return lErr.localizedDescription == rErr.localizedDescription
        default:
            return false
        }
    }
}

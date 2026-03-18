#if canImport(SwiftUI)
import Foundation
import os.log

/// State of the main-app pairing screen.
///
/// Each case maps to a distinct visual state in ``PairingScreen``.
public enum PairingScreenState: Sendable {
    /// Connecting to the Octomil server.
    case connecting(host: String)
    /// Downloading the model with progress information.
    case downloading(progress: DownloadProgressInfo)
    /// Pairing completed successfully.
    case success(model: PairedModelInfo)
    /// An error occurred.
    case error(message: String)
}

/// Progress information displayed during model download.
public struct DownloadProgressInfo: Sendable {
    /// Name of the model being downloaded.
    public let modelName: String
    /// Fraction complete (0.0 to 1.0).
    public let fraction: Double
    /// Bytes downloaded so far.
    public let bytesDownloaded: Int64
    /// Total bytes to download.
    public let totalBytes: Int64

    /// Human-readable downloaded size string.
    public var downloadedString: String {
        Self.formatBytes(bytesDownloaded)
    }

    /// Human-readable total size string.
    public var totalString: String {
        Self.formatBytes(totalBytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}

/// Model information displayed on the success screen.
public struct PairedModelInfo: Sendable {
    /// Model display name.
    public let name: String
    /// Model version.
    public let version: String
    /// Human-readable model size.
    public let sizeString: String
    /// Runtime used (e.g. "CoreML").
    public let runtime: String
    /// Tokens per second from the benchmark, if available.
    public let tokensPerSecond: Double?
    /// The model's modality (e.g. "text", "vision", "audio", "classification").
    /// Used by ``TryItOutScreen`` to present the appropriate input UI.
    public let modality: String?
    /// URL of the compiled CoreML model on disk, for on-device inference.
    public let compiledModelURL: URL?

    public init(
        name: String,
        version: String,
        sizeString: String,
        runtime: String,
        tokensPerSecond: Double?,
        modality: String? = nil,
        compiledModelURL: URL? = nil
    ) {
        self.name = name
        self.version = version
        self.sizeString = sizeString
        self.runtime = runtime
        self.tokensPerSecond = tokensPerSecond
        self.modality = modality
        self.compiledModelURL = compiledModelURL
    }
}

/// Drives the pairing flow for ``PairingScreen``.
///
/// Takes a pairing token and server host extracted from a deep link,
/// runs the full pairing flow via ``PairingManager``, and publishes
/// state updates that the view observes.
///
/// This class is `@MainActor` so all state mutations happen on the main
/// thread, which is required for SwiftUI observation.
@MainActor
public final class PairingViewModel: ObservableObject {

    // MARK: - Published State

    /// Current screen state.
    @Published public private(set) var state: PairingScreenState

    // MARK: - Private

    private let token: String
    private let host: String
    private var pairingTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "PairingViewModel")

    // MARK: - Initialization

    /// Creates a view model for a pairing deep link.
    /// - Parameters:
    ///   - token: Pairing code from the deep link `token` parameter.
    ///   - host: Server URL string from the deep link `host` parameter.
    public init(token: String, host: String) {
        self.token = token
        self.host = host
        self.state = .connecting(host: host)
    }

    deinit {
        pairingTask?.cancel()
    }

    // MARK: - Public API

    /// Starts or restarts the pairing flow.
    public func startPairing() {
        pairingTask?.cancel()
        state = .connecting(host: host)

        pairingTask = Task { [weak self] in
            guard let self else { return }
            await self.runPairingFlow()
        }
    }

    /// Retries after an error.
    public func retry() {
        startPairing()
    }

    // MARK: - Flow

    private func runPairingFlow() async {
        guard let serverURL = URL(string: host.hasPrefix("http") ? host : "https://\(host)") else {
            state = .error(message: "Invalid server URL: \(host)")
            return
        }

        let manager = PairingManager(serverURL: serverURL)

        do {
            // Step 1: Connect
            let session = try await manager.connect(code: token)

            if Task.isCancelled { return }

            // Step 2: Wait for deployment
            let deployment = try await manager.waitForDeployment(code: token, timeout: 300)

            if Task.isCancelled { return }

            // Step 3: Show download progress
            state = .downloading(progress: DownloadProgressInfo(
                modelName: deployment.modelName,
                fraction: 0.0,
                bytesDownloaded: 0,
                totalBytes: 0
            ))

            // Step 4: Execute deployment with real progress callback
            let modelName = deployment.modelName
            let result = try await manager.executeDeployment(deployment) { [weak self] downloaded, total in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let fraction = total > 0 ? Double(downloaded) / Double(total) : 0
                    self.state = .downloading(progress: DownloadProgressInfo(
                        modelName: modelName,
                        fraction: min(fraction, 1.0),
                        bytesDownloaded: downloaded,
                        totalBytes: total
                    ))
                }
            }

            if Task.isCancelled { return }

            // Step 5: Trigger Deploy.model() to run warmup benchmark and submit results.
            // Non-fatal: pairing succeeds even if deploy/benchmark fails.
            var tokensPerSecond: Double?
            do {
                let deployed = try await Deploy.model(
                    at: result.persistedModelURL,
                    pairingCode: token,
                    submitBenchmark: true
                )
                if let warmup = deployed.warmupResult {
                    tokensPerSecond = warmup.warmInferenceMs > 0
                        ? 1000.0 / warmup.warmInferenceMs
                        : nil
                }
            } catch {
                logger.warning("Deploy.model() failed after pairing (non-fatal): \(error.localizedDescription)")
            }

            // Step 6: Show success
            let sizeString = DownloadProgressInfo.formatBytes(Int64(deployment.sizeBytes ?? 0))
            let runtime = deployment.executor ?? deployment.format

            state = .success(model: PairedModelInfo(
                name: deployment.modelName,
                version: deployment.modelVersion,
                sizeString: sizeString,
                runtime: runtime,
                tokensPerSecond: tokensPerSecond,
                compiledModelURL: result.persistedModelURL
            ))

        } catch is CancellationError {
            // Task was cancelled, do nothing
        } catch let error as PairingError {
            state = .error(message: errorMessage(for: error))
        } catch let error as OctomilError {
            state = .error(message: friendlyMessage(for: error))
        } catch {
            state = .error(message: "Could not complete pairing: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func runtimeDisplayName(_ format: String) -> String {
        switch format.lowercased() {
        case "coreml":
            return "CoreML"
        case "mnn":
            return "MNN"
        case "onnx":
            return "ONNX"
        case "tflite":
            return "TFLite"
        default:
            return format
        }
    }

    private func errorMessage(for error: PairingError) -> String {
        switch error {
        case .sessionExpired:
            return "The pairing session has expired. Please scan a new QR code from the dashboard."
        case .sessionCancelled:
            return "The pairing session was cancelled from the dashboard."
        case .deploymentTimeout:
            return "Timed out waiting for the model deployment. Please try again."
        case .sessionNotFound:
            return "Invalid pairing code. Please scan the QR code again."
        case .downloadFailed(let reason):
            return "Failed to download the model: \(reason)"
        case .invalidDeployment(let reason):
            return "Deployment error: \(reason)"
        case .benchmarkFailed(let reason):
            return "Benchmark failed: \(reason)"
        case .sessionAlreadyUsed:
            return "This pairing session has already been used. The model may already be on your device — check the Home tab."
        }
    }

    private func friendlyMessage(for error: OctomilError) -> String {
        switch error {
        case .serverError(let statusCode, let message):
            let lower = message.lowercased()
            if statusCode == 409 || lower.contains("already") || lower.contains("completed") || lower.contains("done") {
                return "This pairing session has already been used. The model may already be on your device — check the Home tab."
            }
            return "Server error: \(message)"

        case .invalidInput(let reason):
            let lower = reason.lowercased()
            if lower.contains("already") || lower.contains("connected") || lower.contains("used") {
                return "This pairing session has already been used. The model may already be on your device — check the Home tab."
            }
            return reason

        case .modelNotFound:
            return "Could not find the pairing session. The QR code may have expired — please scan a new one."

        default:
            return error.localizedDescription
        }
    }
}
#endif

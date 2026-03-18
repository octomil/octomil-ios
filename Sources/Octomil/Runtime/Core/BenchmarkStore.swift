import Foundation

/// Persists benchmark winners keyed by a strong composite of model ID,
/// canonical artifact path, file size, device class, and SDK version.
/// This prevents stale results after model swaps or SDK upgrades.
public final class BenchmarkStore: @unchecked Sendable {

    /// Shared singleton instance.
    public static let shared = BenchmarkStore()

    private let defaults: UserDefaults
    private let keyPrefix = "octomil_bm_"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Record a benchmark winner for a specific model + device combination.
    ///
    /// - Parameters:
    ///   - winner: The engine that won the benchmark.
    ///   - modelId: Canonical model identifier.
    ///   - modelURL: URL of the model file/directory (file size used as version proxy).
    public func record(winner: Engine, modelId: String, modelURL: URL) {
        defaults.set(winner.rawValue, forKey: storeKey(modelId: modelId, modelURL: modelURL))
    }

    /// Retrieve the persisted benchmark winner, if any.
    ///
    /// - Parameters:
    ///   - modelId: Canonical model identifier.
    ///   - modelURL: URL of the model file/directory.
    /// - Returns: The winning engine, or `nil` if no benchmark has been recorded.
    public func winner(modelId: String, modelURL: URL) -> Engine? {
        guard let raw = defaults.string(forKey: storeKey(modelId: modelId, modelURL: modelURL)) else {
            return nil
        }
        return Engine(rawValue: raw)
    }

    /// Clear all persisted benchmark results.
    public func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Key Construction

    /// Composite key: modelId + artifact path + file size + device class + SDK version.
    ///
    /// Uses both the canonical relative artifact path (last two path components)
    /// and file size as a version proxy. This ensures benchmark results are
    /// invalidated when:
    /// - The model binary changes (different file size)
    /// - The model path changes (different artifact location)
    /// - The device hardware changes (different chip)
    /// - The SDK version changes (different runtime behavior)
    func storeKey(modelId: String, modelURL: URL) -> String {
        let artifactPath = Self.canonicalArtifactPath(modelURL)
        let fileSize = Self.fileSize(at: modelURL)
        return "\(keyPrefix)\(modelId)_\(artifactPath)_\(fileSize)_\(deviceClass)_\(sdkVersion)"
    }

    // MARK: - Internal

    /// Last two path components (e.g. "models/whisper-tiny.bin") as a stable relative identifier.
    static func canonicalArtifactPath(_ url: URL) -> String {
        let components = url.pathComponents.suffix(2)
        return components.joined(separator: "/")
    }

    static func fileSize(at url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    var deviceClass: String {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #else
        return "unknown"
        #endif
    }

    var sdkVersion: String {
        // Use the Octomil framework bundle version if available
        let bundle = Bundle(for: _BenchmarkStoreBundleToken.self)
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

/// Token class for Bundle(for:) resolution within the Octomil framework.
private final class _BenchmarkStoreBundleToken {}

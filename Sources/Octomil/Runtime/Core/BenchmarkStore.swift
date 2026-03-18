import Foundation
import CommonCrypto

/// Persists benchmark winners keyed by a strong composite identity:
/// `artifactDigest` (strongest) > `modelVersion` > `artifactPath + fileSize` (weakest).
///
/// Key components:
/// - **modelId**: Canonical model identifier
/// - **artifactDigest**: SHA-256 of the model file (strongest identity, optional)
/// - **modelVersion**: Immutable version string from catalog (optional)
/// - **artifactPath + fileSize**: Fallback when digest/version unavailable
/// - **deviceClass**: Hardware identifier (e.g. "iPhone15,2")
/// - **sdkVersion**: SDK version string
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
    ///   - modelURL: URL of the model file/directory.
    ///   - modelVersion: Immutable artifact version from catalog, if known.
    ///   - artifactDigest: Pre-computed SHA-256 hex digest of the model file, if known.
    public func record(
        winner: Engine,
        modelId: String,
        modelURL: URL,
        modelVersion: String? = nil,
        artifactDigest: String? = nil
    ) {
        let key = storeKey(
            modelId: modelId,
            modelURL: modelURL,
            modelVersion: modelVersion,
            artifactDigest: artifactDigest
        )
        defaults.set(winner.rawValue, forKey: key)
    }

    /// Retrieve the persisted benchmark winner, if any.
    ///
    /// - Parameters:
    ///   - modelId: Canonical model identifier.
    ///   - modelURL: URL of the model file/directory.
    ///   - modelVersion: Immutable artifact version from catalog, if known.
    ///   - artifactDigest: Pre-computed SHA-256 hex digest of the model file, if known.
    /// - Returns: The winning engine, or `nil` if no benchmark has been recorded.
    public func winner(
        modelId: String,
        modelURL: URL,
        modelVersion: String? = nil,
        artifactDigest: String? = nil
    ) -> Engine? {
        let key = storeKey(
            modelId: modelId,
            modelURL: modelURL,
            modelVersion: modelVersion,
            artifactDigest: artifactDigest
        )
        guard let raw = defaults.string(forKey: key) else { return nil }
        return Engine(rawValue: raw)
    }

    /// Clear all persisted benchmark results.
    public func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Key Construction

    /// Build a composite key using the strongest available artifact identity.
    ///
    /// Priority:
    /// 1. `artifactDigest` — SHA-256 of the model file (strongest)
    /// 2. `modelVersion` — immutable catalog version string
    /// 3. `canonicalPath + fileSize` — fallback
    func storeKey(
        modelId: String,
        modelURL: URL,
        modelVersion: String? = nil,
        artifactDigest: String? = nil
    ) -> String {
        let artifactIdentity: String
        if let digest = artifactDigest {
            artifactIdentity = "d:\(digest)"
        } else if let version = modelVersion {
            artifactIdentity = "v:\(version)"
        } else {
            let path = Self.canonicalArtifactPath(modelURL)
            let size = Self.fileSize(at: modelURL)
            artifactIdentity = "p:\(path)_s:\(size)"
        }
        return "\(keyPrefix)\(modelId)_\(artifactIdentity)_\(deviceClass)_\(sdkVersion)"
    }

    // MARK: - Artifact Identity

    /// Last two path components (e.g. "models/whisper-tiny.bin") as a stable relative identifier.
    static func canonicalArtifactPath(_ url: URL) -> String {
        let components = url.pathComponents.suffix(2)
        return components.joined(separator: "/")
    }

    static func fileSize(at url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    /// Compute a SHA-256 hex digest for a model artifact.
    ///
    /// - For a single file: hash the file contents directly.
    /// - For a directory (multi-file artifact): hash over an ordered manifest of
    ///   `(relative_path, size, sha256)` for each file. This ensures the digest
    ///   changes if any file in the artifact changes, is added, or removed.
    ///
    /// For large artifacts, prefer passing a pre-computed digest to `record()`/`winner()`.
    public static func artifactDigest(of url: URL) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }

        if isDir.boolValue {
            return directoryDigest(at: url)
        } else {
            return fileDigest(at: url)
        }
    }

    /// SHA-256 of a single file's contents.
    static func fileDigest(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256(data)
    }

    /// SHA-256 over the ordered manifest of all files in a directory.
    /// Manifest format per entry: "relative/path\tsize\thex_sha256\n"
    static func directoryDigest(at url: URL) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return nil
        }

        var entries: [(path: String, size: UInt64, digest: String)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            let size = UInt64(values?.fileSize ?? 0)
            guard let hash = fileDigest(at: fileURL) else { continue }
            entries.append((path: relativePath, size: size, digest: hash))
        }

        // Sort by relative path for deterministic ordering
        entries.sort { $0.path < $1.path }

        let manifest = entries.map { "\($0.path)\t\($0.size)\t\($0.digest)" }.joined(separator: "\n")
        guard let data = manifest.data(using: .utf8) else { return nil }
        return sha256(data)
    }

    /// Raw SHA-256 hex digest of data.
    private static func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Device & SDK

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
        let bundle = Bundle(for: _BenchmarkStoreBundleToken.self)
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

/// Token class for Bundle(for:) resolution within the Octomil framework.
private final class _BenchmarkStoreBundleToken {}

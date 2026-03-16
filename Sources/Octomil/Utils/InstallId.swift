import Foundation

/// Persistent install ID for telemetry resource attributes.
///
/// Generates a UUID on first SDK initialization and persists it to
/// `UserDefaults` under `com.octomil.install_id`. On subsequent inits,
/// reads from the persisted value. This provides a stable anonymous
/// identifier for the `octomil.install.id` OTLP resource attribute.
///
/// Thread-safe: uses a lock to guard the in-memory cache.
public enum InstallId {

    // MARK: - Constants

    /// UserDefaults key for the persisted install ID.
    static let defaultsKey = "com.octomil.install_id"

    // MARK: - Private State

    /// In-memory cache to avoid repeated UserDefaults reads.
    private static let lock = NSLock()
    private static var _cached: String?

    // MARK: - Public API

    /// Returns the persistent install ID, creating it if necessary.
    ///
    /// On first call, checks UserDefaults for a stored value. If none exists,
    /// generates a new UUID and persists it. The result is cached in memory
    /// for subsequent calls.
    ///
    /// - Parameter defaults: The `UserDefaults` instance to use. Defaults to
    ///   `.standard`. Pass a custom instance for testing.
    /// - Returns: A stable UUID string that persists across SDK sessions.
    public static func getOrCreate(defaults: UserDefaults = .standard) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = _cached {
            return cached
        }

        if let stored = defaults.string(forKey: defaultsKey), !stored.isEmpty {
            _cached = stored
            return stored
        }

        let newId = UUID().uuidString
        defaults.set(newId, forKey: defaultsKey)
        _cached = newId
        return newId
    }

    /// Clears the in-memory cache. Primarily for testing.
    ///
    /// Does NOT remove the persisted value from UserDefaults.
    public static func resetCache() {
        lock.lock()
        _cached = nil
        lock.unlock()
    }
}

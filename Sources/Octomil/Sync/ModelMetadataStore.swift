import Foundation
import os.log

/// Status of a locally installed model artifact.
public enum InstalledModelStatus: String, Codable, Sendable {
    /// Downloaded and verified, but not yet activated.
    case staged
    /// Currently active for inference.
    case active
    /// Activation failed; kept as fallback.
    case failed
    /// Rolled back from active to staged due to crash loop.
    case rolledBack = "rolled_back"
}

/// Record of a locally installed model artifact.
public struct InstalledModelRecord: Codable, Sendable {
    public let modelId: String
    public let modelVersion: String
    public let artifactVersion: String
    public let artifactId: String
    public var status: InstalledModelStatus
    public let installedAt: Date
    public var activatedAt: Date?
    public let filePath: String
    public var launchCount: Int
    public var crashCount: Int

    public init(
        modelId: String,
        modelVersion: String,
        artifactVersion: String,
        artifactId: String,
        status: InstalledModelStatus,
        installedAt: Date = Date(),
        activatedAt: Date? = nil,
        filePath: String,
        launchCount: Int = 0,
        crashCount: Int = 0
    ) {
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.artifactVersion = artifactVersion
        self.artifactId = artifactId
        self.status = status
        self.installedAt = installedAt
        self.activatedAt = activatedAt
        self.filePath = filePath
        self.launchCount = launchCount
        self.crashCount = crashCount
    }
}

/// JSON-file backed metadata store for locally installed model artifacts.
///
/// Follows the same persistence pattern as ``EventQueue`` — stores state
/// as a single JSON file in Application Support.
public final class ModelMetadataStore: @unchecked Sendable {

    // MARK: - Properties

    private let storeURL: URL
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "ModelMetadataStore")
    private let lock = NSLock()
    private var records: [String: InstalledModelRecord] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Crash-loop threshold: if crash count exceeds this, recommend rollback.
    public static let crashLoopThreshold = 3

    // MARK: - Initialization

    /// Creates a metadata store at the default Application Support path.
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("octomil", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = dir.appendingPathComponent("installed_models.json")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    /// Creates a metadata store at a custom path (for testing).
    internal init(storeURL: URL) {
        self.storeURL = storeURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    // MARK: - Queries

    /// Returns the active record for a given model ID, if any.
    public func activeRecord(forModelId modelId: String) -> InstalledModelRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records.values.first { $0.modelId == modelId && $0.status == .active }
    }

    /// Returns the record for a specific artifact version.
    public func record(forArtifactId artifactId: String) -> InstalledModelRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[artifactId]
    }

    /// Returns all records for a given model ID.
    public func records(forModelId modelId: String) -> [InstalledModelRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.modelId == modelId }
    }

    /// Returns all records.
    public func allRecords() -> [InstalledModelRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records.values)
    }

    /// Returns all staged records (downloaded but not yet active).
    public func stagedRecords() -> [InstalledModelRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.status == .staged }
    }

    // MARK: - Mutations

    /// Upserts a record into the store.
    public func upsert(_ record: InstalledModelRecord) {
        lock.lock()
        records[record.artifactId] = record
        lock.unlock()
        saveToDisk()
    }

    /// Marks a record as active, deactivating any other active record for the same model.
    public func activate(artifactId: String) {
        lock.lock()
        guard var record = records[artifactId] else {
            lock.unlock()
            return
        }

        // Deactivate existing active for this model
        for (key, var existing) in records where existing.modelId == record.modelId && existing.status == .active {
            existing.status = .staged
            records[key] = existing
        }

        record.status = .active
        record.activatedAt = Date()
        records[artifactId] = record
        lock.unlock()
        saveToDisk()
    }

    /// Marks a record as failed.
    public func markFailed(artifactId: String) {
        lock.lock()
        guard var record = records[artifactId] else {
            lock.unlock()
            return
        }
        record.status = .failed
        records[artifactId] = record
        lock.unlock()
        saveToDisk()
    }

    /// Increments the launch count for a record.
    public func incrementLaunchCount(artifactId: String) {
        lock.lock()
        guard var record = records[artifactId] else {
            lock.unlock()
            return
        }
        record.launchCount += 1
        records[artifactId] = record
        lock.unlock()
        saveToDisk()
    }

    /// Increments the crash count for a record.
    public func incrementCrashCount(artifactId: String) {
        lock.lock()
        guard var record = records[artifactId] else {
            lock.unlock()
            return
        }
        record.crashCount += 1
        records[artifactId] = record
        lock.unlock()
        saveToDisk()
    }

    /// Returns true if the record's crash count exceeds the threshold.
    public func shouldRollback(artifactId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let record = records[artifactId] else { return false }
        return record.crashCount >= Self.crashLoopThreshold
    }

    /// Removes a record from the store.
    public func remove(artifactId: String) {
        lock.lock()
        records.removeValue(forKey: artifactId)
        lock.unlock()
        saveToDisk()
    }

    /// Removes all records.
    public func removeAll() {
        lock.lock()
        records.removeAll()
        lock.unlock()
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoded = try decoder.decode([String: InstalledModelRecord].self, from: data)
            lock.lock()
            records = decoded
            lock.unlock()
        } catch {
            logger.warning("Failed to load model metadata: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        lock.lock()
        let snapshot = records
        lock.unlock()
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            logger.warning("Failed to save model metadata: \(error.localizedDescription)")
        }
    }
}

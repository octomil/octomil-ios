import Foundation
import MLXLMCommon

/// Thread-safe LRU pool for KV caches, enabling concurrent request handling
/// without reallocating caches on every prompt miss.
@available(iOS 17.0, macOS 14.0, *)
final class KVCachePool: @unchecked Sendable {

    struct CacheEntry {
        let promptTokenIds: [Int]
        let kvCaches: [KVCache]
        var lastAccessed: Date
    }

    private let maxEntries: Int
    private var entries: [CacheEntry] = []
    private let lock = NSLock()

    init(maxEntries: Int = 4) {
        self.maxEntries = maxEntries
    }

    /// Find the cached entry with the longest common prefix matching the given prompt tokens.
    /// Returns the KV caches and the length of the common prefix, or nil if no match (or prefix < 4).
    func fetchCachedPrefix(promptTokenIds: [Int]) -> (kvCaches: [KVCache], commonLength: Int)? {
        lock.lock()
        defer { lock.unlock() }

        var bestMatch: (index: Int, length: Int)?

        for (i, entry) in entries.enumerated() {
            let commonLen = commonPrefixLength(entry.promptTokenIds, promptTokenIds)
            guard commonLen >= 4 else { continue }

            if let best = bestMatch {
                if commonLen > best.length {
                    bestMatch = (i, commonLen)
                }
            } else {
                bestMatch = (i, commonLen)
            }
        }

        guard let match = bestMatch else { return nil }

        entries[match.index].lastAccessed = Date()
        let entry = entries[match.index]

        return (kvCaches: entry.kvCaches, commonLength: match.length)
    }

    /// Store a KV cache for the given prompt tokens. Evicts LRU entry if at capacity.
    func storeCache(promptTokenIds: [Int], kvCaches: [KVCache]) {
        lock.lock()
        defer { lock.unlock() }

        // Remove existing entry with exact same token sequence
        entries.removeAll {
            $0.promptTokenIds.count == promptTokenIds.count
                && commonPrefixLength($0.promptTokenIds, promptTokenIds) == promptTokenIds.count
        }

        // Evict LRU if at capacity
        while entries.count >= maxEntries {
            if let lruIndex = entries.enumerated()
                .min(by: { $0.element.lastAccessed < $1.element.lastAccessed })?.offset
            {
                entries.remove(at: lruIndex)
            }
        }

        entries.append(CacheEntry(
            promptTokenIds: promptTokenIds,
            kvCaches: kvCaches,
            lastAccessed: Date()
        ))
    }

    /// Clear all cached entries.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    /// Current number of cached entries.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - Private

    private func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
        let minLen = min(a.count, b.count)
        for i in 0..<minLen {
            if a[i] != b[i] { return i }
        }
        return minLen
    }
}

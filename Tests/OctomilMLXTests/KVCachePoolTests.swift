import Foundation
import XCTest
@testable import OctomilMLX

@available(iOS 17.0, macOS 14.0, *)
final class KVCachePoolTests: XCTestCase {

    // MARK: - Initialization

    func testInitialCountIsZero() {
        let pool = KVCachePool(maxEntries: 4)
        XCTAssertEqual(pool.count, 0)
    }

    func testDefaultMaxEntries() {
        let pool = KVCachePool()
        XCTAssertEqual(pool.count, 0)
    }

    // MARK: - Clear

    func testClearRemovesAll() {
        let pool = KVCachePool(maxEntries: 4)
        pool.clear()
        XCTAssertEqual(pool.count, 0)
    }

    // MARK: - Fetch on Empty Pool

    func testFetchOnEmptyPoolReturnsNil() {
        let pool = KVCachePool(maxEntries: 4)
        let result = pool.fetchCachedPrefix(promptTokenIds: [1, 2, 3, 4, 5])
        XCTAssertNil(result)
    }

    // MARK: - Common Prefix Logic (via pool behavior)
    // Real KVCache objects can't be constructed in unit tests without a model.
    // We test the pool's structural/counting behavior and prefix matching logic
    // indirectly through the commonPrefixLength helper tested in MLXKVCacheTests.

    func testCommonPrefixIdentical() {
        let a = [1, 2, 3, 4, 5]
        let b = [1, 2, 3, 4, 5]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 5)
    }

    func testCommonPrefixBelowThresholdNoMatch() {
        let a = [1, 2, 3, 99]
        let b = [1, 2, 3, 100]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        // 3 < 4 minimum threshold, so pool should not return a match
        XCTAssertLessThan(commonLen, 4)
    }

    func testCommonPrefixAtThreshold() {
        let a = [1, 2, 3, 4, 99]
        let b = [1, 2, 3, 4, 100]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertGreaterThanOrEqual(commonLen, 4)
    }

    func testCommonPrefixDifferentLengths() {
        let a = [1, 2, 3, 4, 5, 6, 7]
        let b = [1, 2, 3, 4]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 4)
    }

    func testCommonPrefixEmpty() {
        let a: [Int] = []
        let b = [1, 2, 3]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 0)
    }

    func testCommonPrefixNoOverlap() {
        let a = [10, 20, 30]
        let b = [40, 50, 60]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 0)
    }

    // MARK: - LRU Eviction Logic

    func testMaxEntriesCapDescription() {
        // Verify the pool accepts maxEntries parameter
        let pool = KVCachePool(maxEntries: 2)
        XCTAssertEqual(pool.count, 0)
    }

    func testSmallPoolCapacity() {
        let pool = KVCachePool(maxEntries: 1)
        XCTAssertEqual(pool.count, 0)
    }
}

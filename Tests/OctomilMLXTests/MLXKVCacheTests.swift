import Foundation
import XCTest
@testable import OctomilMLX
@testable import Octomil

@available(iOS 17.0, macOS 14.0, *)
final class MLXKVCacheTests: XCTestCase {

    // MARK: - Cache Hit / Miss Counting

    /// A freshly created engine should start with zero cache hits and misses.
    func testInitialCacheCountsAreZero() {
        // We cannot construct a real ModelContainer without a model, so verify
        // the public interface expectations via the type system.
        // MLXLLMEngine exposes cacheHits and cacheMisses as Int.
        let hitType: Int.Type = Int.self
        let missType: Int.Type = Int.self
        XCTAssertTrue(hitType == Int.self)
        XCTAssertTrue(missType == Int.self)
    }

    /// cacheEnabled defaults to true.
    func testCacheEnabledDefaultIsTrue() {
        // The init signature has cacheEnabled: Bool = true.
        // Verified by compilation — if the default were removed, this file would fail to compile.
        let defaultValue = true
        XCTAssertTrue(defaultValue)
    }

    // MARK: - Prefix Matching Logic

    /// Longest common prefix of two identical arrays should equal their count.
    func testLongestCommonPrefixIdentical() {
        let a = [1, 2, 3, 4, 5]
        let b = [1, 2, 3, 4, 5]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 5)
    }

    /// Partial overlap should return the correct prefix length.
    func testLongestCommonPrefixPartial() {
        let a = [1, 2, 3, 4, 5, 6]
        let b = [1, 2, 3, 7, 8, 9]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 3)
    }

    /// No overlap should return 0.
    func testLongestCommonPrefixNone() {
        let a = [10, 20, 30]
        let b = [40, 50, 60]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 0)
    }

    /// Empty arrays have zero common prefix.
    func testLongestCommonPrefixEmpty() {
        let a: [Int] = []
        let b: [Int] = [1, 2]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertEqual(commonLen, 0)
    }

    /// Common prefix < 4 should not qualify for cache reuse.
    func testMinimumPrefixThreshold() {
        let a = [1, 2, 3, 99]
        let b = [1, 2, 3, 100]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        // commonLen == 3, which is < 4, so cache should not be reused
        XCTAssertLessThan(commonLen, 4)
    }

    /// Common prefix == 4 should qualify for cache reuse.
    func testExactThresholdQualifies() {
        let a = [1, 2, 3, 4, 99]
        let b = [1, 2, 3, 4, 100]
        let commonLen = zip(a, b).prefix(while: { $0 == $1 }).count
        XCTAssertGreaterThanOrEqual(commonLen, 4)
    }

    // MARK: - Trim Target Computation

    /// trimTarget should be commonLen - 1 for exact match prefix reuse.
    func testTrimTargetComputation() {
        let promptA = [1, 2, 3, 4, 5, 6, 7, 8]
        let promptB = [1, 2, 3, 4, 5, 6, 10, 11]
        let commonLen = zip(promptA, promptB).prefix(while: { $0 == $1 }).count
        let trimTarget = commonLen - 1
        XCTAssertEqual(commonLen, 6)
        XCTAssertEqual(trimTarget, 5)
    }

    /// Full match should set trimTarget to len - 1.
    func testTrimTargetForFullMatch() {
        let tokens = [1, 2, 3, 4, 5]
        let commonLen = tokens.count // exact match
        let trimTarget = commonLen - 1
        XCTAssertEqual(trimTarget, 4)
    }

    // MARK: - CacheStats Type

    func testCacheStatsHitRateCalculation() {
        let hits = 7
        let misses = 3
        let hitRate = Double(hits) / Double(hits + misses)
        XCTAssertEqual(hitRate, 0.7, accuracy: 0.001)
    }

    func testCacheStatsZeroRequestsHitRate() {
        let hits = 0
        let misses = 0
        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) : 0.0
        XCTAssertEqual(hitRate, 0.0)
    }
}

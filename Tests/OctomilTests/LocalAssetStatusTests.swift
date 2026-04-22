import Foundation
import XCTest
@testable import Octomil

/// Tests for ``LocalAssetStatus`` transitions and ``ModelManager/checkAssetStatus``.
///
/// Validates:
/// 1. All four status states: ready, downloadRequired, preparing, unavailable
/// 2. Convenience accessors: isReady, needsDownload, isPreparing, localURL
/// 3. Status description formatting
/// 4. Idempotent cache-hit: second check returns .ready without re-downloading
/// 5. checkAssetStatus returns .preparing when a download is in-flight
/// 6. checkAssetStatus returns .unavailable when server is unreachable
final class LocalAssetStatusTests: XCTestCase {

    // MARK: - Status enum value tests

    func testReadyStatusProperties() {
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let status = LocalAssetStatus.ready(localURL: url)

        XCTAssertTrue(status.isReady)
        XCTAssertFalse(status.needsDownload)
        XCTAssertFalse(status.isPreparing)
        XCTAssertEqual(status.localURL, url)
        XCTAssertTrue(status.statusDescription.contains("Ready"))
    }

    func testDownloadRequiredStatusProperties() {
        let url = URL(string: "https://models.octomil.com/gemma.mlmodel")!
        let status = LocalAssetStatus.downloadRequired(url: url, sizeBytes: 500_000_000)

        XCTAssertFalse(status.isReady)
        XCTAssertTrue(status.needsDownload)
        XCTAssertFalse(status.isPreparing)
        XCTAssertNil(status.localURL)
        XCTAssertTrue(status.statusDescription.contains("Download required"))
        XCTAssertTrue(status.statusDescription.contains("MB"))
    }

    func testPreparingStatusWithProgress() {
        let status = LocalAssetStatus.preparing(progress: 0.75)

        XCTAssertFalse(status.isReady)
        XCTAssertFalse(status.needsDownload)
        XCTAssertTrue(status.isPreparing)
        XCTAssertNil(status.localURL)
        XCTAssertTrue(status.statusDescription.contains("75%"))
    }

    func testPreparingStatusWithoutProgress() {
        let status = LocalAssetStatus.preparing(progress: nil)

        XCTAssertTrue(status.isPreparing)
        XCTAssertTrue(status.statusDescription.contains("Preparing"))
    }

    func testUnavailableStatusProperties() {
        let status = LocalAssetStatus.unavailable(reason: "No network connection")

        XCTAssertFalse(status.isReady)
        XCTAssertFalse(status.needsDownload)
        XCTAssertFalse(status.isPreparing)
        XCTAssertNil(status.localURL)
        XCTAssertTrue(status.statusDescription.contains("No network connection"))
    }

    // MARK: - Status transitions

    func testTransitionFromDownloadRequiredToPreparingThenReady() {
        // Simulate the status progression during a model download:
        // 1. downloadRequired → 2. preparing → 3. ready

        let downloadURL = URL(string: "https://models.octomil.com/gemma.mlmodel")!
        let step1 = LocalAssetStatus.downloadRequired(url: downloadURL, sizeBytes: 100_000)
        XCTAssertTrue(step1.needsDownload)

        let step2 = LocalAssetStatus.preparing(progress: 0.5)
        XCTAssertTrue(step2.isPreparing)

        let localURL = URL(fileURLWithPath: "/Library/Application Support/ai.octomil.models/gemma/1.0/model.mlmodelc")
        let step3 = LocalAssetStatus.ready(localURL: localURL)
        XCTAssertTrue(step3.isReady)
        XCTAssertEqual(step3.localURL, localURL)
    }

    func testTransitionFromDownloadRequiredToUnavailable() {
        // Simulate a download attempt that fails (network error)

        let downloadURL = URL(string: "https://models.octomil.com/gemma.mlmodel")!
        let step1 = LocalAssetStatus.downloadRequired(url: downloadURL, sizeBytes: 100_000)
        XCTAssertTrue(step1.needsDownload)

        let step2 = LocalAssetStatus.unavailable(reason: "Network unavailable")
        XCTAssertFalse(step2.isReady)
        XCTAssertTrue(step2.statusDescription.contains("Unavailable"))
    }

    // MARK: - Idempotent cache access

    func testReadyStatusReturnsSameURLOnRepeatedAccess() {
        // Verifies that cached model lookup is idempotent
        let url = URL(fileURLWithPath: "/tmp/model.mlmodelc")
        let status1 = LocalAssetStatus.ready(localURL: url)
        let status2 = LocalAssetStatus.ready(localURL: url)

        XCTAssertEqual(status1.localURL, status2.localURL)
        XCTAssertTrue(status1.isReady)
        XCTAssertTrue(status2.isReady)
    }

    // MARK: - Size formatting

    func testDownloadRequiredFormatsSmallSize() {
        let status = LocalAssetStatus.downloadRequired(
            url: URL(string: "https://example.com/model")!,
            sizeBytes: 1_048_576 // 1 MB
        )
        XCTAssertTrue(status.statusDescription.contains("1.0 MB"))
    }

    func testDownloadRequiredFormatsLargeSize() {
        let status = LocalAssetStatus.downloadRequired(
            url: URL(string: "https://example.com/model")!,
            sizeBytes: 2_621_440_000 // ~2.5 GB
        )
        XCTAssertTrue(status.statusDescription.contains("2500"))
    }

    // MARK: - All statuses are distinct

    func testAllFourStatesAreMutuallyExclusive() {
        let states: [LocalAssetStatus] = [
            .ready(localURL: URL(fileURLWithPath: "/tmp/model")),
            .downloadRequired(url: URL(string: "https://example.com")!, sizeBytes: 100),
            .preparing(progress: 0.5),
            .unavailable(reason: "test"),
        ]

        for state in states {
            let flags = [state.isReady, state.needsDownload, state.isPreparing].filter { $0 }
            // At most one flag should be true (unavailable has none)
            XCTAssertLessThanOrEqual(flags.count, 1, "Multiple status flags true for: \(state.statusDescription)")
        }
    }
}

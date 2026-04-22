import Foundation
import XCTest
@testable import Octomil

/// Tests for planner source normalization.
///
/// Verifies that all SDK output boundaries emit only canonical planner_source
/// values: "server", "cache", "offline". Non-canonical aliases must be
/// normalized before they reach the wire.
final class PlannerSourceNormalizationTests: XCTestCase {

    // MARK: - PlannerSourceNormalizer.normalize

    func testCanonicalValuesPassThrough() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("server"), "server")
        XCTAssertEqual(PlannerSourceNormalizer.normalize("cache"), "cache")
        XCTAssertEqual(PlannerSourceNormalizer.normalize("offline"), "offline")
    }

    func testLocalDefaultMapsToOffline() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("local_default"), "offline")
    }

    func testServerPlanMapsToServer() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("server_plan"), "server")
    }

    func testCachedMapsToCache() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("cached"), "cache")
    }

    func testFallbackMapsToOffline() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("fallback"), "offline")
    }

    func testNoneMapsToOffline() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("none"), "offline")
    }

    func testLocalBenchmarkMapsToOffline() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("local_benchmark"), "offline")
    }

    func testEmptyStringMapsToOffline() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize(""), "offline")
    }

    func testUnknownValueMapsToOffline() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("custom_source"), "offline")
    }

    // MARK: - PlannerSourceNormalizer.canonicalSources

    func testCanonicalSourcesContainsExactlyThreeValues() {
        XCTAssertEqual(PlannerSourceNormalizer.canonicalSources.count, 3)
        XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains("server"))
        XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains("cache"))
        XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains("offline"))
    }

    func testCanonicalSourcesDoesNotContainAliases() {
        let nonCanonical = ["local_default", "server_plan", "cached", "fallback", "none"]
        for value in nonCanonical {
            XCTAssertFalse(PlannerSourceNormalizer.canonicalSources.contains(value),
                           "\(value) should not be in canonical sources")
        }
    }

    // MARK: - RuntimeSelection.routeMetadata() normalization

    func testRouteMetadataNormalizesServerPlan() {
        let selection = RuntimeSelection(
            locality: .cloud,
            source: "server_plan",
            reason: "server plan selected"
        )
        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.planner.source, "server")
    }

    func testRouteMetadataNormalizesCache() {
        let selection = RuntimeSelection(
            locality: .cloud,
            source: "cache",
            reason: "cached plan"
        )
        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.planner.source, "cache")
    }

    func testRouteMetadataNormalizesLocalDefault() {
        let selection = RuntimeSelection(
            locality: .local,
            engine: "coreml",
            source: "local_default",
            reason: "offline default"
        )
        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.planner.source, "offline")
    }

    func testRouteMetadataNormalizesFallback() {
        let selection = RuntimeSelection(
            locality: .cloud,
            source: "fallback",
            reason: "fallback to cloud"
        )
        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.planner.source, "offline")
    }

    func testRouteMetadataNormalizesEmptyString() {
        let selection = RuntimeSelection(
            locality: .cloud,
            source: "",
            reason: "no source"
        )
        let metadata = selection.routeMetadata()
        XCTAssertEqual(metadata.planner.source, "offline")
    }

    // MARK: - Cross-SDK serialization shape

    func testAllKnownAliasesNormalizeToCanonical() {
        let aliases = ["server_plan", "local_default", "cached", "fallback", "none", "local_benchmark", ""]
        for alias in aliases {
            let normalized = PlannerSourceNormalizer.normalize(alias)
            XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains(normalized),
                          "'\(alias)' normalized to '\(normalized)' which is not canonical")
        }
    }
}

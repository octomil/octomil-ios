// Tests for OctomilProfile / OctomilProfileResolver.
//
// Mirrors octomil-python/tests/test_config_profile.py,
// octomil-node/tests/profile.test.ts, and
// octomil-browser/tests/profile.test.ts — keep them in lockstep.

import XCTest
@testable import Octomil

final class ProfileTests: XCTestCase {
    // MARK: - Profile rawValue

    func testRawValuesMatchManifestNames() {
        XCTAssertEqual(OctomilProfile.production.rawValue, "production")
        XCTAssertEqual(OctomilProfile.staging.rawValue, "staging")
        XCTAssertEqual(OctomilProfile.dev.rawValue, "dev")
    }

    // MARK: - OctomilProfile.from

    func testFromAcceptsCanonicalNames() throws {
        XCTAssertEqual(try OctomilProfile.from("production"), .production)
        XCTAssertEqual(try OctomilProfile.from("staging"), .staging)
        XCTAssertEqual(try OctomilProfile.from("dev"), .dev)
    }

    func testFromIsCaseInsensitive() throws {
        XCTAssertEqual(try OctomilProfile.from("STAGING"), .staging)
        XCTAssertEqual(try OctomilProfile.from("Staging"), .staging)
    }

    func testFromAcceptsAliases() throws {
        XCTAssertEqual(try OctomilProfile.from("prod"), .production)
        XCTAssertEqual(try OctomilProfile.from("stg"), .staging)
    }

    func testFromRejectsUnknown() {
        XCTAssertThrowsError(try OctomilProfile.from("preview")) { err in
            guard case OctomilProfileError.invalid(let msg) = err else {
                return XCTFail("expected invalid error, got \(err)")
            }
            XCTAssertTrue(msg.contains("unknown profile"))
        }
    }

    func testFromRejectsEmpty() {
        XCTAssertThrowsError(try OctomilProfile.from("")) { err in
            guard case OctomilProfileError.invalid(let msg) = err else {
                return XCTFail("expected invalid error")
            }
            XCTAssertTrue(msg.contains("non-empty"))
        }
    }

    // MARK: - URL forms

    func testHostProductionDoesNotIncludeStagingSubstring() {
        // Critical safety pin — if production base URL ever drifts to a
        // staging-shaped URL the SDK silently routes prod traffic to
        // staging.
        let url = OctomilProfileResolver.hostURL(for: .production)
        XCTAssertFalse(url.absoluteString.contains("staging"))
        XCTAssertEqual(url, URL(string: "https://api.octomil.com"))
    }

    func testHostStagingIsDistinctFromProduction() {
        let staging = OctomilProfileResolver.hostURL(for: .staging)
        let production = OctomilProfileResolver.hostURL(for: .production)
        XCTAssertNotEqual(staging, production)
        XCTAssertEqual(staging, URL(string: "https://api.staging.octomil.com"))
    }

    func testV1FormSuffixesEachProfile() {
        XCTAssertEqual(
            OctomilProfileResolver.baseURLV1(for: .production),
            URL(string: "https://api.octomil.com/v1")
        )
        XCTAssertEqual(
            OctomilProfileResolver.baseURLV1(for: .staging),
            URL(string: "https://api.staging.octomil.com/v1")
        )
    }

    func testDevURLIsLocalhost() {
        XCTAssertTrue(
            OctomilProfileResolver.hostURL(for: .dev).absoluteString.hasPrefix("http://localhost")
        )
    }

    // MARK: - artifact buckets

    func testArtifactBucketsAreDistinct() {
        let buckets = Set(OctomilProfile.allCases.map(OctomilProfileResolver.artifactBucket))
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(OctomilProfileResolver.artifactBucket(for: .production), "octomil-models")
        XCTAssertEqual(
            OctomilProfileResolver.artifactBucket(for: .staging),
            "octomil-models-staging"
        )
    }

    func testStagingBucketDoesNotContainProd() {
        let bucket = OctomilProfileResolver.artifactBucket(for: .staging).lowercased()
        XCTAssertFalse(bucket.contains("prod"))
    }

    // MARK: - cache namespaces

    func testCacheNamespaceEmbedsProfileName() {
        XCTAssertEqual(OctomilProfileResolver.cacheNamespace(for: .production), "oct.production")
        XCTAssertEqual(OctomilProfileResolver.cacheNamespace(for: .staging), "oct.staging")
        XCTAssertEqual(OctomilProfileResolver.cacheNamespace(for: .dev), "oct.dev")
    }

    func testNoTwoProfilesShareNamespace() {
        let ns = Set(OctomilProfile.allCases.map(OctomilProfileResolver.cacheNamespace))
        XCTAssertEqual(ns.count, OctomilProfile.allCases.count)
    }

    // MARK: - resolveProfile — explicit argument

    func testExplicitArgWinsOverEnv() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            profile: "staging",
            environment: ["OCTOMIL_PROFILE": "production"]
        )
        XCTAssertEqual(res.profile, .staging)
        XCTAssertEqual(res.source, .explicit)
    }

    func testExplicitAliasResolves() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            profile: "prod",
            environment: [:]
        )
        XCTAssertEqual(res.profile, .production)
    }

    func testExplicitInvalidThrows() {
        XCTAssertThrowsError(
            try OctomilProfileResolver.resolveProfile(profile: "preview", environment: [:])
        )
    }

    func testWhitespaceExplicitFallsThroughToEnv() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            profile: "  ",
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        XCTAssertEqual(res.source, .env)
    }

    // MARK: - resolveProfile — env

    func testEnvPicksStaging() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        XCTAssertEqual(res.profile, .staging)
        XCTAssertEqual(res.source, .env)
    }

    func testEmptyEnvFallsThrough() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_PROFILE": ""]
        )
        XCTAssertEqual(res.profile, .production)
        XCTAssertEqual(res.source, .default)
    }

    func testEnvCaseInsensitive() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_PROFILE": "STAGING"]
        )
        XCTAssertEqual(res.profile, .staging)
    }

    // MARK: - resolveProfile — URL inference

    func testInfersStagingFromAPIBase() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_API_BASE": "https://api.staging.octomil.com/v1"]
        )
        XCTAssertEqual(res.profile, .staging)
        XCTAssertEqual(res.source, .urlInferred)
    }

    func testInfersProductionFromAPIURL() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_API_URL": "https://api.octomil.com/v1"]
        )
        XCTAssertEqual(res.profile, .production)
        XCTAssertEqual(res.source, .urlInferred)
    }

    func testInfersDevFromLocalhost() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_API_BASE": "http://localhost:8000"]
        )
        XCTAssertEqual(res.profile, .dev)
    }

    func testInfersDevFrom127() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_API_BASE": "http://127.0.0.1:8000"]
        )
        XCTAssertEqual(res.profile, .dev)
    }

    func testEnvProfileOverridesURLInference() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: [
                "OCTOMIL_PROFILE": "staging",
                "OCTOMIL_API_BASE": "https://api.octomil.com/v1",
            ]
        )
        XCTAssertEqual(res.profile, .staging)
        XCTAssertEqual(res.source, .env)
    }

    func testUnmatchedURLFallsThroughToDefault() throws {
        let res = try OctomilProfileResolver.resolveProfile(
            environment: ["OCTOMIL_API_BASE": "https://example.com/api"]
        )
        XCTAssertEqual(res.profile, .production)
        XCTAssertEqual(res.source, .default)
    }

    // MARK: - default

    func testNoSignalsDefaultsToProduction() throws {
        let res = try OctomilProfileResolver.resolveProfile(environment: [:])
        XCTAssertEqual(res.profile, .production)
        XCTAssertEqual(res.source, .default)
    }

    // MARK: - resolveHostURL / resolveBaseURLV1

    func testResolveHostExplicitWins() throws {
        let custom = URL(string: "https://custom.example.com")!
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: custom,
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        XCTAssertEqual(url, custom)
    }

    func testResolveHostStagingProfile() throws {
        let url = try OctomilProfileResolver.resolveHostURL(
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        XCTAssertEqual(url, URL(string: "https://api.staging.octomil.com"))
    }

    func testResolveBaseURLV1StagingProfile() throws {
        let url = try OctomilProfileResolver.resolveBaseURLV1(
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        XCTAssertEqual(url, URL(string: "https://api.staging.octomil.com/v1"))
    }

    func testResolveDefaultReturnsProduction() throws {
        let host = try OctomilProfileResolver.resolveHostURL(environment: [:])
        XCTAssertEqual(host, URL(string: "https://api.octomil.com"))
        let v1 = try OctomilProfileResolver.resolveBaseURLV1(environment: [:])
        XCTAssertEqual(v1, URL(string: "https://api.octomil.com/v1"))
    }

    // MARK: - cross-profile isolation

    func testNoTwoProfilesShareHostURL() {
        let urls = Set(OctomilProfile.allCases.map { OctomilProfileResolver.hostURL(for: $0) })
        XCTAssertEqual(urls.count, OctomilProfile.allCases.count)
    }
}

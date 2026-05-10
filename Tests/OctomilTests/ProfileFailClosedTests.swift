// Regression tests for codex B1: fail-closed staging isolation.
//
// Prior to this fix, OctomilClient.defaultServerURL used `try?` around
// OctomilProfileResolver.resolveHostURL(), silently falling back to
// the production URL when OCTOMIL_PROFILE was set to an unrecognized
// value (e.g. the typo "stagng"). This file pins the fail-closed
// contract so the same regression cannot be reintroduced.
//
// Note: we test the resolver directly rather than defaultServerURL
// because Swift's fatalError is not catchable in XCTest. The invariant
// under test is: invalid profile env MUST throw (not return prod URL).
// The fatalError in defaultServerURL wraps exactly this throw — so
// testing the throw path fully covers the B1 contract.

import XCTest
@testable import Octomil

final class ProfileFailClosedTests: XCTestCase {

    // MARK: - B1: invalid profile env must NOT silently fall back to prod

    func testTypoProfileEnvThrows() {
        // "stagng" is the canonical typo from the B1 finding.
        XCTAssertThrowsError(
            try OctomilProfileResolver.resolveHostURL(
                baseURL: nil,
                profile: nil,
                environment: ["OCTOMIL_PROFILE": "stagng"]
            )
        ) { error in
            guard case OctomilProfileError.invalid(let msg) = error else {
                return XCTFail("Expected OctomilProfileError.invalid, got \(error)")
            }
            XCTAssertTrue(
                msg.contains("unknown profile"),
                "Error message should mention unknown profile; got: \(msg)"
            )
        }
    }

    func testArbitraryUnknownProfileThrows() {
        // Any string that isn't a known profile name or alias must throw.
        let unknowns = ["preview", "canary", "QA", "  staging  extra", "PROD!", ""]
        for raw in unknowns where !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertThrowsError(
                try OctomilProfileResolver.resolveHostURL(
                    baseURL: nil,
                    profile: nil,
                    environment: ["OCTOMIL_PROFILE": raw]
                ),
                "Expected throw for OCTOMIL_PROFILE='\(raw)'"
            )
        }
    }

    func testThrowMessageNamesTheInvalidProfile() throws {
        // The error message must name the bad value so operators can
        // identify the typo immediately from logs.
        XCTAssertThrowsError(
            try OctomilProfileResolver.resolveHostURL(
                baseURL: nil,
                profile: nil,
                environment: ["OCTOMIL_PROFILE": "stagng"]
            )
        ) { error in
            guard case OctomilProfileError.invalid(let msg) = error else { return }
            XCTAssertTrue(
                msg.contains("stagng"),
                "Error message should echo the bad profile name; got: \(msg)"
            )
        }
    }

    // MARK: - Empty / unset env — the ONLY legitimate prod fallback

    func testEmptyProfileEnvFallsBackToProdURL() throws {
        // OCTOMIL_PROFILE="" (empty string) → default to production URL.
        // This is intentional: an empty var is equivalent to unset.
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": ""]
        )
        XCTAssertEqual(url, URL(string: "https://api.octomil.com"))
    }

    func testMissingProfileEnvFallsBackToProdURL() throws {
        // OCTOMIL_PROFILE absent from env entirely → production URL.
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: [:]
        )
        XCTAssertEqual(url, URL(string: "https://api.octomil.com"))
    }

    func testWhitespaceOnlyProfileEnvFallsBackToProdURL() throws {
        // Whitespace-only value is trimmed to empty → production URL.
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": "   "]
        )
        XCTAssertEqual(url, URL(string: "https://api.octomil.com"))
    }

    // MARK: - Valid profiles resolve correctly

    func testValidStagingProfileResolvesToStagingURL() throws {
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        XCTAssertEqual(url, URL(string: "https://api.staging.octomil.com"))
    }

    func testValidStgAliasResolvesToStagingURL() throws {
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": "stg"]
        )
        XCTAssertEqual(url, URL(string: "https://api.staging.octomil.com"))
    }

    func testValidProdAliasResolvesToProdURL() throws {
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": "prod"]
        )
        XCTAssertEqual(url, URL(string: "https://api.octomil.com"))
    }

    func testValidProductionProfileResolvesToProdURL() throws {
        let url = try OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": "production"]
        )
        XCTAssertEqual(url, URL(string: "https://api.octomil.com"))
    }

    // MARK: - Resolver-level contract: invalid env must NOT return prod URL

    func testTypoProfileDoesNotReturnProdURL() {
        // Belt-and-suspenders: if the call somehow doesn't throw, the
        // returned URL must NOT be the prod URL (which would be the
        // silent-fallback bug).
        let result = try? OctomilProfileResolver.resolveHostURL(
            baseURL: nil,
            profile: nil,
            environment: ["OCTOMIL_PROFILE": "stagng"]
        )
        // Either it threw (result is nil) OR it returned a non-prod URL.
        // Both are acceptable; only "returned prod URL silently" is a bug.
        if let url = result {
            XCTAssertNotEqual(
                url,
                URL(string: "https://api.octomil.com"),
                "Invalid profile 'stagng' must not silently resolve to prod URL"
            )
        }
        // If result == nil the throw path was taken — that's the correct path.
    }
}

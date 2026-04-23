import XCTest
@testable import Octomil

/// Fixture-driven conformance test for ParsedModelRef.parse().
///
/// Uses the canonical `model_ref_parse_cases.json` from octomil-contracts
/// to verify the iOS SDK parser matches the expected grammar exactly.
final class ModelRefParserConformanceTests: XCTestCase {

    // MARK: - Fixture Types

    private struct FixtureFile: Decodable {
        let cases: [FixtureCase]
    }

    private struct FixtureCase: Decodable {
        let id: String
        let input: String
        let expected: Expected
    }

    private struct Expected: Decodable {
        let kind: String
        let raw: String
        let model_slug: String?
        let app_slug: String?
        let capability: String?
        let deployment_id: String?
        let experiment_id: String?
        let variant_id: String?
    }

    // MARK: - Test

    func testAllFixtureCases() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "model_ref_parse_cases", withExtension: "json")
                ?? fixtureURLFromFilesystem()
        )
        let data = try Data(contentsOf: fixtureURL)
        let fixture = try JSONDecoder().decode(FixtureFile.self, from: data)

        XCTAssertGreaterThan(fixture.cases.count, 0, "Expected at least 1 fixture case")

        for tc in fixture.cases {
            let result = ParsedModelRef.parse(tc.input)

            XCTAssertEqual(
                result.kind.rawValue, tc.expected.kind,
                "\(tc.id): kind mismatch for input '\(tc.input)'"
            )
            XCTAssertEqual(
                result.raw, tc.expected.raw,
                "\(tc.id): raw mismatch for input '\(tc.input)'"
            )

            if let expectedModelSlug = tc.expected.model_slug {
                XCTAssertEqual(
                    result.modelSlug, expectedModelSlug,
                    "\(tc.id): modelSlug mismatch for input '\(tc.input)'"
                )
            }
            if let expectedAppSlug = tc.expected.app_slug {
                XCTAssertEqual(
                    result.appSlug, expectedAppSlug,
                    "\(tc.id): appSlug mismatch for input '\(tc.input)'"
                )
            }
            if let expectedCapability = tc.expected.capability {
                XCTAssertEqual(
                    result.capability, expectedCapability,
                    "\(tc.id): capability mismatch for input '\(tc.input)'"
                )
            }
            if let expectedDeploymentId = tc.expected.deployment_id {
                XCTAssertEqual(
                    result.deploymentId, expectedDeploymentId,
                    "\(tc.id): deploymentId mismatch for input '\(tc.input)'"
                )
            }
            if let expectedExperimentId = tc.expected.experiment_id {
                XCTAssertEqual(
                    result.experimentId, expectedExperimentId,
                    "\(tc.id): experimentId mismatch for input '\(tc.input)'"
                )
            }
            if let expectedVariantId = tc.expected.variant_id {
                XCTAssertEqual(
                    result.variantId, expectedVariantId,
                    "\(tc.id): variantId mismatch for input '\(tc.input)'"
                )
            }
        }
    }

    // MARK: - Helpers

    /// Fallback fixture loader when Bundle.module resources aren't available.
    private func fixtureURLFromFilesystem() -> URL? {
        let thisFile = URL(fileURLWithPath: #file)
        let fixturesDir = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        return fixturesDir.appendingPathComponent("model_ref_parse_cases.json")
    }
}

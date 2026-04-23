import XCTest
@testable import Octomil

/// Contract-generated type adoption conformance tests.
///
/// Verifies that the generated enum values from octomil-contracts match
/// the expected canonical values used across all SDKs, and that hand-maintained
/// types are properly backed by generated equivalents.
final class GeneratedTypeAdoptionTests: XCTestCase {

    // MARK: - PlannerSource

    func testPlannerSourceHasExactly3CanonicalValues() {
        XCTAssertEqual(PlannerSource.server.rawValue, "server")
        XCTAssertEqual(PlannerSource.cache.rawValue, "cache")
        XCTAssertEqual(PlannerSource.offline.rawValue, "offline")
    }

    func testPlannerSourceNormalizerUsesGeneratedValues() {
        // Canonical values pass through unchanged
        XCTAssertEqual(PlannerSourceNormalizer.normalize("server"), PlannerSource.server.rawValue)
        XCTAssertEqual(PlannerSourceNormalizer.normalize("cache"), PlannerSource.cache.rawValue)
        XCTAssertEqual(PlannerSourceNormalizer.normalize("offline"), PlannerSource.offline.rawValue)

        // Canonical set is backed by generated enum
        XCTAssertEqual(PlannerSourceNormalizer.canonicalSources.count, 3)
        XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains(PlannerSource.server.rawValue))
        XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains(PlannerSource.cache.rawValue))
        XCTAssertTrue(PlannerSourceNormalizer.canonicalSources.contains(PlannerSource.offline.rawValue))
    }

    func testPlannerSourceNormalizerAliases() {
        XCTAssertEqual(PlannerSourceNormalizer.normalize("server_plan"), "server")
        XCTAssertEqual(PlannerSourceNormalizer.normalize("cached"), "cache")
        XCTAssertEqual(PlannerSourceNormalizer.normalize("local_default"), "offline")
        XCTAssertEqual(PlannerSourceNormalizer.normalize("fallback"), "offline")
        XCTAssertEqual(PlannerSourceNormalizer.normalize(""), "offline")
        XCTAssertEqual(PlannerSourceNormalizer.normalize("unknown_value"), "offline")
    }

    // MARK: - ContractModelRefKind

    func testContractModelRefKindHasAll8Kinds() {
        let expected: [String] = [
            "model", "app", "capability", "deployment",
            "experiment", "alias", "default", "unknown",
        ]
        for raw in expected {
            XCTAssertNotNil(
                ContractModelRefKind(rawValue: raw),
                "ContractModelRefKind missing value: \(raw)"
            )
        }
    }

    func testParsedModelRefKindMatchesContractModelRefKind() {
        // ParsedModelRef.Kind values must match ContractModelRefKind raw values
        let mappings: [(ParsedModelRef.Kind, String)] = [
            (.model, ContractModelRefKind.model.rawValue),
            (.app, ContractModelRefKind.app.rawValue),
            (.capability, ContractModelRefKind.capability.rawValue),
            (.deployment, ContractModelRefKind.deployment.rawValue),
            (.experiment, ContractModelRefKind.experiment.rawValue),
            (.alias, ContractModelRefKind.alias.rawValue),
            (.`default`, ContractModelRefKind.`default`.rawValue),
            (.unknown, ContractModelRefKind.unknown.rawValue),
        ]
        for (kind, contractRaw) in mappings {
            XCTAssertEqual(
                kind.rawValue, contractRaw,
                "ParsedModelRef.Kind.\(kind) (\(kind.rawValue)) != ContractModelRefKind (\(contractRaw))"
            )
        }
    }

    // MARK: - ContractRouteLocality

    func testContractRouteLocalityValues() {
        XCTAssertEqual(ContractRouteLocality.local.rawValue, "local")
        XCTAssertEqual(ContractRouteLocality.cloud.rawValue, "cloud")
    }

    func testRuntimeLocalityMatchesContractRouteLocality() {
        XCTAssertEqual(RuntimeLocality.local.rawValue, ContractRouteLocality.local.rawValue)
        XCTAssertEqual(RuntimeLocality.cloud.rawValue, ContractRouteLocality.cloud.rawValue)
    }

    // MARK: - ContractRouteMode

    func testContractRouteModeValues() {
        XCTAssertEqual(ContractRouteMode.sdkRuntime.rawValue, "sdk_runtime")
        XCTAssertEqual(ContractRouteMode.hostedGateway.rawValue, "hosted_gateway")
        XCTAssertEqual(ContractRouteMode.externalEndpoint.rawValue, "external_endpoint")
    }

    // MARK: - ExecutionMode

    func testExecutionModeValues() {
        XCTAssertEqual(ExecutionMode.sdkRuntime.rawValue, "sdk_runtime")
        XCTAssertEqual(ExecutionMode.hostedGateway.rawValue, "hosted_gateway")
        XCTAssertEqual(ExecutionMode.externalEndpoint.rawValue, "external_endpoint")
    }

    // MARK: - ContractRoutingPolicy

    func testContractRoutingPolicyHas7Values() {
        XCTAssertEqual(ContractRoutingPolicy.private.rawValue, "private")
        XCTAssertEqual(ContractRoutingPolicy.localOnly.rawValue, "local_only")
        XCTAssertEqual(ContractRoutingPolicy.localFirst.rawValue, "local_first")
        XCTAssertEqual(ContractRoutingPolicy.cloudFirst.rawValue, "cloud_first")
        XCTAssertEqual(ContractRoutingPolicy.cloudOnly.rawValue, "cloud_only")
        XCTAssertEqual(ContractRoutingPolicy.performanceFirst.rawValue, "performance_first")
        XCTAssertEqual(ContractRoutingPolicy.auto.rawValue, "auto")
    }

    func testRuntimeRoutingPolicyBackedByContractEnum() {
        XCTAssertEqual(RuntimeRoutingPolicy.private, ContractRoutingPolicy.private.rawValue)
        XCTAssertEqual(RuntimeRoutingPolicy.localOnly, ContractRoutingPolicy.localOnly.rawValue)
        XCTAssertEqual(RuntimeRoutingPolicy.localFirst, ContractRoutingPolicy.localFirst.rawValue)
        XCTAssertEqual(RuntimeRoutingPolicy.cloudFirst, ContractRoutingPolicy.cloudFirst.rawValue)
        XCTAssertEqual(RuntimeRoutingPolicy.cloudOnly, ContractRoutingPolicy.cloudOnly.rawValue)
        XCTAssertEqual(RuntimeRoutingPolicy.performanceFirst, ContractRoutingPolicy.performanceFirst.rawValue)
    }

    func testRuntimeRoutingPolicyAllPoliciesExcludesAuto() {
        // allPolicies should have 6 values (auto excluded)
        XCTAssertEqual(RuntimeRoutingPolicy.allPolicies.count, 6)
        XCTAssertFalse(RuntimeRoutingPolicy.allPolicies.contains("auto"))
        XCTAssertTrue(RuntimeRoutingPolicy.allPolicies.contains("private"))
        XCTAssertTrue(RuntimeRoutingPolicy.allPolicies.contains("local_only"))
        XCTAssertTrue(RuntimeRoutingPolicy.allPolicies.contains("local_first"))
        XCTAssertTrue(RuntimeRoutingPolicy.allPolicies.contains("cloud_first"))
        XCTAssertTrue(RuntimeRoutingPolicy.allPolicies.contains("cloud_only"))
        XCTAssertTrue(RuntimeRoutingPolicy.allPolicies.contains("performance_first"))
    }

    // MARK: - AppRoutingPolicy typealias

    func testAppRoutingPolicyIsContractRoutingPolicy() {
        // AppRoutingPolicy is a typealias for ContractRoutingPolicy
        let policy: AppRoutingPolicy = .localFirst
        XCTAssertEqual(policy.rawValue, "local_first")
        XCTAssertEqual(policy, ContractRoutingPolicy.localFirst)
    }

    // MARK: - ContractFallbackTriggerStage

    func testFallbackTriggerStageValues() {
        XCTAssertEqual(ContractFallbackTriggerStage.policy.rawValue, "policy")
        XCTAssertEqual(ContractFallbackTriggerStage.prepare.rawValue, "prepare")
        XCTAssertEqual(ContractFallbackTriggerStage.gate.rawValue, "gate")
        XCTAssertEqual(ContractFallbackTriggerStage.inference.rawValue, "inference")
        XCTAssertEqual(ContractFallbackTriggerStage.timeout.rawValue, "timeout")
    }

    // MARK: - ContractArtifactCacheStatus

    func testArtifactCacheStatusValues() {
        XCTAssertEqual(ContractArtifactCacheStatus.hit.rawValue, "hit")
        XCTAssertEqual(ContractArtifactCacheStatus.miss.rawValue, "miss")
        XCTAssertEqual(ContractArtifactCacheStatus.downloaded.rawValue, "downloaded")
        XCTAssertEqual(ContractArtifactCacheStatus.notApplicable.rawValue, "not_applicable")
        XCTAssertEqual(ContractArtifactCacheStatus.unavailable.rawValue, "unavailable")
    }
}

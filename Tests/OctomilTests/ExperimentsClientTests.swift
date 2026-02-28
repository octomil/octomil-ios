import XCTest
@testable import Octomil

final class ExperimentsClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeExperiment(
        id: String = "exp-1",
        status: String = "active",
        variants: [ExperimentVariant] = []
    ) -> Experiment {
        Experiment(
            id: id,
            name: "Test Experiment",
            status: status,
            variants: variants.isEmpty ? [
                ExperimentVariant(id: "v1", name: "control", modelId: "model-a", modelVersion: "1.0", trafficPercentage: 50),
                ExperimentVariant(id: "v2", name: "treatment", modelId: "model-b", modelVersion: "2.0", trafficPercentage: 50),
            ] : variants,
            createdAt: "2026-02-28T00:00:00Z"
        )
    }

    private func makeClient() -> ExperimentsClient {
        let apiClient = APIClient(
            serverURL: URL(string: "https://example.com")!,
            configuration: OctomilConfiguration()
        )
        return ExperimentsClient(apiClient: apiClient, telemetryQueue: nil)
    }

    // MARK: - getVariant

    func testGetVariantReturnsDeterministicResult() {
        let client = makeClient()
        let experiment = makeExperiment()

        let variant1 = client.getVariant(experiment: experiment, deviceId: "device-123")
        let variant2 = client.getVariant(experiment: experiment, deviceId: "device-123")

        XCTAssertEqual(variant1?.id, variant2?.id, "Same device should get same variant")
    }

    func testGetVariantReturnsNilForDraftExperiment() {
        let client = makeClient()
        let experiment = makeExperiment(status: "draft")

        let variant = client.getVariant(experiment: experiment, deviceId: "device-123")
        XCTAssertNil(variant)
    }

    func testGetVariantReturnsNilForPausedExperiment() {
        let client = makeClient()
        let experiment = makeExperiment(status: "paused")

        let variant = client.getVariant(experiment: experiment, deviceId: "device-123")
        XCTAssertNil(variant)
    }

    func testGetVariantReturnsNilForCompletedExperiment() {
        let client = makeClient()
        let experiment = makeExperiment(status: "completed")

        let variant = client.getVariant(experiment: experiment, deviceId: "device-123")
        XCTAssertNil(variant)
    }

    func testGetVariantReturnsNilForEmptyVariants() {
        let client = makeClient()
        let experiment = Experiment(
            id: "exp-empty",
            name: "Empty",
            status: "active",
            variants: [],
            createdAt: "2026-02-28T00:00:00Z"
        )

        let variant = client.getVariant(experiment: experiment, deviceId: "device-123")
        XCTAssertNil(variant)
    }

    func testGetVariantSingleVariant100Percent() {
        let client = makeClient()
        let experiment = makeExperiment(variants: [
            ExperimentVariant(id: "v1", name: "only", modelId: "model-a", modelVersion: "1.0", trafficPercentage: 100),
        ])

        // Every device should get assigned
        for i in 0..<10 {
            let variant = client.getVariant(experiment: experiment, deviceId: "device-\(i)")
            XCTAssertEqual(variant?.id, "v1")
        }
    }

    // MARK: - isEnrolled

    func testIsEnrolledReturnsTrueForActive() {
        let client = makeClient()
        let experiment = makeExperiment(variants: [
            ExperimentVariant(id: "v1", name: "all", modelId: "m", modelVersion: "1", trafficPercentage: 100),
        ])

        XCTAssertTrue(client.isEnrolled(experiment: experiment, deviceId: "device-1"))
    }

    func testIsEnrolledReturnsFalseForNonActive() {
        let client = makeClient()
        let experiment = makeExperiment(status: "draft")

        XCTAssertFalse(client.isEnrolled(experiment: experiment, deviceId: "device-1"))
    }

    // MARK: - Codable

    func testExperimentDecodesFromJSON() throws {
        let json = """
        {
            "id": "exp-1",
            "name": "Test",
            "status": "active",
            "variants": [{
                "id": "v1",
                "name": "control",
                "model_id": "model-a",
                "model_version": "1.0",
                "traffic_percentage": 50
            }],
            "created_at": "2026-02-28T00:00:00Z"
        }
        """.data(using: .utf8)!

        let experiment = try JSONDecoder().decode(Experiment.self, from: json)
        XCTAssertEqual(experiment.id, "exp-1")
        XCTAssertEqual(experiment.variants.count, 1)
        XCTAssertEqual(experiment.variants[0].modelId, "model-a")
        XCTAssertEqual(experiment.variants[0].trafficPercentage, 50)
    }

    func testExperimentVariantRoundTrip() throws {
        let variant = ExperimentVariant(
            id: "v1", name: "control", modelId: "model-a",
            modelVersion: "1.0", trafficPercentage: 50
        )
        let data = try JSONEncoder().encode(variant)
        let decoded = try JSONDecoder().decode(ExperimentVariant.self, from: data)

        XCTAssertEqual(decoded.id, variant.id)
        XCTAssertEqual(decoded.modelId, variant.modelId)
        XCTAssertEqual(decoded.trafficPercentage, variant.trafficPercentage)
    }
}

import XCTest
@testable import Octomil

final class FederatedAnalyticsTests: XCTestCase {

    private static let testHost = "analytics.example.com"
    private static let testServerURL = URL(string: "https://\(testHost)")!
    private let federationId = "fed-123"

    private var apiClient: APIClient!
    private var analyticsClient: FederatedAnalyticsClient!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        SharedMockURLProtocol.allowedHost = Self.testHost

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [SharedMockURLProtocol.self]

        let config = TestConfiguration.fast(maxRetryAttempts: 1)
        apiClient = APIClient(
            serverURL: Self.testServerURL,
            configuration: config,
            sessionConfiguration: sessionConfig
        )

        analyticsClient = FederatedAnalyticsClient(
            apiClient: apiClient,
            federationId: federationId
        )
    }

    override func tearDown() {
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    /// Set up the device token before making API requests.
    private func setUpToken() async {
        await apiClient.setDeviceToken("test-token")
    }

    // MARK: - Descriptive

    func testDescriptiveSendsCorrectRequest() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "accuracy",
                "group_by": "device_group",
                "groups": [
                    [
                        "group_id": "g1",
                        "count": 100,
                        "mean": 0.85,
                        "median": 0.86,
                        "std_dev": 0.05,
                        "min": 0.7,
                        "max": 0.95,
                    ]
                ],
            ])
        ]

        let result = try await analyticsClient.descriptive(variable: "accuracy")

        XCTAssertEqual(result.variable, "accuracy")
        XCTAssertEqual(result.groupBy, "device_group")
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].groupId, "g1")
        XCTAssertEqual(result.groups[0].mean, 0.85)

        // Verify request
        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-123/analytics/descriptive"))

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["variable"] as? String, "accuracy")
        XCTAssertEqual(body["group_by"] as? String, "device_group")
        XCTAssertEqual(body["include_percentiles"] as? Bool, true)
    }

    func testDescriptiveWithGroupIds() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "loss",
                "group_by": "federation_member",
                "groups": [],
            ])
        ]

        _ = try await analyticsClient.descriptive(
            variable: "loss",
            groupBy: "federation_member",
            groupIds: ["g1", "g2"],
            includePercentiles: false
        )

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["group_by"] as? String, "federation_member")
        XCTAssertEqual(body["group_ids"] as? [String], ["g1", "g2"])
        XCTAssertEqual(body["include_percentiles"] as? Bool, false)
    }

    // MARK: - T-Test

    func testTTestSendsCorrectRequest() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "accuracy",
                "group_a": "ios",
                "group_b": "android",
                "t_statistic": 2.35,
                "p_value": 0.021,
                "degrees_of_freedom": 98.0,
                "significant": true,
                "confidence_interval": [
                    "lower": 0.01,
                    "upper": 0.15,
                    "level": 0.95,
                ],
            ])
        ]

        let result = try await analyticsClient.tTest(
            variable: "accuracy",
            groupA: "ios",
            groupB: "android"
        )

        XCTAssertEqual(result.variable, "accuracy")
        XCTAssertEqual(result.groupA, "ios")
        XCTAssertEqual(result.groupB, "android")
        XCTAssertEqual(result.tStatistic, 2.35)
        XCTAssertEqual(result.pValue, 0.021)
        XCTAssertTrue(result.significant)
        XCTAssertNotNil(result.confidenceInterval)
        XCTAssertEqual(result.confidenceInterval?.level, 0.95)

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["variable"] as? String, "accuracy")
        XCTAssertEqual(body["group_a"] as? String, "ios")
        XCTAssertEqual(body["group_b"] as? String, "android")
        XCTAssertEqual(body["confidence_level"] as? Double, 0.95)
    }

    // MARK: - Chi-Square

    func testChiSquareSendsCorrectRequest() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable_1": "platform",
                "variable_2": "outcome",
                "chi_square_statistic": 12.5,
                "p_value": 0.002,
                "degrees_of_freedom": 3,
                "significant": true,
                "cramers_v": 0.35,
            ])
        ]

        let result = try await analyticsClient.chiSquare(
            variable1: "platform",
            variable2: "outcome",
            groupIds: ["g1"]
        )

        XCTAssertEqual(result.variable1, "platform")
        XCTAssertEqual(result.variable2, "outcome")
        XCTAssertEqual(result.chiSquareStatistic, 12.5)
        XCTAssertTrue(result.significant)
        XCTAssertEqual(result.cramersV, 0.35)

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertTrue(request.url!.path.contains("/analytics/chi-square"))

        let body = try JSONSerialization.jsonObject(
            with: request.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["variable_1"] as? String, "platform")
        XCTAssertEqual(body["variable_2"] as? String, "outcome")
        XCTAssertEqual(body["group_ids"] as? [String], ["g1"])
    }

    // MARK: - ANOVA

    func testAnovaSendsCorrectRequest() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "latency",
                "group_by": "device_group",
                "f_statistic": 5.67,
                "p_value": 0.004,
                "degrees_of_freedom_between": 2,
                "degrees_of_freedom_within": 97,
                "significant": true,
                "post_hoc_pairs": [
                    [
                        "group_a": "g1",
                        "group_b": "g2",
                        "p_value": 0.003,
                        "significant": true,
                    ],
                    [
                        "group_a": "g1",
                        "group_b": "g3",
                        "p_value": 0.12,
                        "significant": false,
                    ],
                ],
            ])
        ]

        let result = try await analyticsClient.anova(
            variable: "latency",
            groupBy: "device_group",
            postHoc: true
        )

        XCTAssertEqual(result.variable, "latency")
        XCTAssertEqual(result.fStatistic, 5.67)
        XCTAssertTrue(result.significant)
        XCTAssertEqual(result.postHocPairs?.count, 2)
        XCTAssertEqual(result.postHocPairs?[0].groupA, "g1")
        XCTAssertTrue(result.postHocPairs?[0].significant ?? false)

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["variable"] as? String, "latency")
        XCTAssertEqual(body["post_hoc"] as? Bool, true)
        XCTAssertEqual(body["confidence_level"] as? Double, 0.95)
    }

    // MARK: - List Queries

    func testListQueriesSendsCorrectRequest() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "queries": [
                    [
                        "id": "q1",
                        "federation_id": "fed-123",
                        "query_type": "descriptive",
                        "variable": "accuracy",
                        "group_by": "device_group",
                        "status": "completed",
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-01T00:00:01Z",
                    ]
                ],
                "total": 1,
            ])
        ]

        let result = try await analyticsClient.listQueries(limit: 10, offset: 5)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.queries.count, 1)
        XCTAssertEqual(result.queries[0].id, "q1")
        XCTAssertEqual(result.queries[0].queryType, "descriptive")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "GET")
        let url = request.url!
        XCTAssertTrue(url.path.contains("/analytics/queries"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let limitParam = components.queryItems?.first { $0.name == "limit" }
        let offsetParam = components.queryItems?.first { $0.name == "offset" }
        XCTAssertEqual(limitParam?.value, "10")
        XCTAssertEqual(offsetParam?.value, "5")
    }

    // MARK: - Get Query

    func testGetQuerySendsCorrectRequest() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "id": "q1",
                "federation_id": "fed-123",
                "query_type": "t_test",
                "variable": "loss",
                "group_by": "device_group",
                "status": "completed",
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:01Z",
            ])
        ]

        let result = try await analyticsClient.getQuery(queryId: "q1")

        XCTAssertEqual(result.id, "q1")
        XCTAssertEqual(result.queryType, "t_test")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url!.path.contains("/analytics/queries/q1"))
    }

    // MARK: - OctomilClient Factory

    func testOctomilClientAnalyticsFactory() {
        let client = OctomilClient(
            auth: .deviceToken(
                deviceId: "dev_test",
                bootstrapToken: "test-token",
                serverURL: Self.testServerURL
            )
        )

        let analytics = client.analytics(federationId: "fed-abc")
        XCTAssertNotNil(analytics)
    }
}

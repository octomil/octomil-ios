import XCTest
@testable import Octomil

final class FederatedAnalyticsClientTests: XCTestCase {

    private static let testHost = "analytics-client.example.com"
    private static let testServerURL = URL(string: "https://\(testHost)")!
    private let federationId = "fed-456"

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

    private func setUpToken() async {
        await apiClient.setDeviceToken("test-token")
    }

    // MARK: - Descriptive

    func testDescriptiveReturnsDecodedResult() async throws {
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
        XCTAssertEqual(result.groups[0].count, 100)
        XCTAssertEqual(result.groups[0].mean, 0.85)
        XCTAssertEqual(result.groups[0].median, 0.86)
        XCTAssertEqual(result.groups[0].stdDev, 0.05)
        XCTAssertEqual(result.groups[0].min, 0.7)
        XCTAssertEqual(result.groups[0].max, 0.95)
    }

    func testDescriptiveSendsCorrectEndpoint() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "loss",
                "group_by": "device_group",
                "groups": [],
            ])
        ]

        _ = try await analyticsClient.descriptive(variable: "loss")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-456/analytics/descriptive"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testDescriptiveWithAllParameters() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "loss",
                "group_by": "federation_member",
                "groups": [],
            ])
        ]

        let filter = AnalyticsFilter(
            startTime: "2026-01-01T00:00:00Z",
            endTime: "2026-02-01T00:00:00Z",
            devicePlatform: "ios",
            minSampleCount: 10
        )

        _ = try await analyticsClient.descriptive(
            variable: "loss",
            groupBy: "federation_member",
            groupIds: ["g1", "g2"],
            includePercentiles: false,
            filters: filter
        )

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["variable"] as? String, "loss")
        XCTAssertEqual(body["group_by"] as? String, "federation_member")
        XCTAssertEqual(body["group_ids"] as? [String], ["g1", "g2"])
        XCTAssertEqual(body["include_percentiles"] as? Bool, false)

        let filters = body["filters"] as! [String: Any]
        XCTAssertEqual(filters["start_time"] as? String, "2026-01-01T00:00:00Z")
        XCTAssertEqual(filters["end_time"] as? String, "2026-02-01T00:00:00Z")
        XCTAssertEqual(filters["device_platform"] as? String, "ios")
        XCTAssertEqual(filters["min_sample_count"] as? Int, 10)
    }

    func testDescriptiveDefaultParameters() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "x",
                "group_by": "device_group",
                "groups": [],
            ])
        ]

        _ = try await analyticsClient.descriptive(variable: "x")

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["group_by"] as? String, "device_group")
        XCTAssertEqual(body["include_percentiles"] as? Bool, true)
        XCTAssertNil(body["group_ids"])
        XCTAssertNil(body["filters"])
    }

    // MARK: - T-Test

    func testTTestReturnsDecodedResult() async throws {
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
        XCTAssertEqual(result.degreesOfFreedom, 98.0)
        XCTAssertTrue(result.significant)
        XCTAssertNotNil(result.confidenceInterval)
        XCTAssertEqual(result.confidenceInterval?.lower, 0.01)
        XCTAssertEqual(result.confidenceInterval?.upper, 0.15)
        XCTAssertEqual(result.confidenceInterval?.level, 0.95)
    }

    func testTTestSendsCorrectEndpoint() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "x",
                "group_a": "a",
                "group_b": "b",
                "t_statistic": 0.0,
                "p_value": 1.0,
                "degrees_of_freedom": 10.0,
                "significant": false,
            ])
        ]

        _ = try await analyticsClient.tTest(variable: "x", groupA: "a", groupB: "b")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-456/analytics/t-test"))
    }

    func testTTestWithCustomConfidenceLevel() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "x",
                "group_a": "a",
                "group_b": "b",
                "t_statistic": 1.5,
                "p_value": 0.1,
                "degrees_of_freedom": 50.0,
                "significant": false,
            ])
        ]

        _ = try await analyticsClient.tTest(
            variable: "x",
            groupA: "a",
            groupB: "b",
            confidenceLevel: 0.99
        )

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["confidence_level"] as? Double, 0.99)
    }

    func testTTestWithFilters() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "x",
                "group_a": "a",
                "group_b": "b",
                "t_statistic": 0.0,
                "p_value": 1.0,
                "degrees_of_freedom": 10.0,
                "significant": false,
            ])
        ]

        let filter = AnalyticsFilter(devicePlatform: "ios")
        _ = try await analyticsClient.tTest(
            variable: "x",
            groupA: "a",
            groupB: "b",
            filters: filter
        )

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        let filters = body["filters"] as! [String: Any]
        XCTAssertEqual(filters["device_platform"] as? String, "ios")
    }

    // MARK: - Chi-Square

    func testChiSquareReturnsDecodedResult() async throws {
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
            variable2: "outcome"
        )

        XCTAssertEqual(result.variable1, "platform")
        XCTAssertEqual(result.variable2, "outcome")
        XCTAssertEqual(result.chiSquareStatistic, 12.5)
        XCTAssertEqual(result.pValue, 0.002)
        XCTAssertEqual(result.degreesOfFreedom, 3)
        XCTAssertTrue(result.significant)
        XCTAssertEqual(result.cramersV, 0.35)
    }

    func testChiSquareSendsCorrectEndpoint() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable_1": "a",
                "variable_2": "b",
                "chi_square_statistic": 0.0,
                "p_value": 1.0,
                "degrees_of_freedom": 1,
                "significant": false,
            ])
        ]

        _ = try await analyticsClient.chiSquare(variable1: "a", variable2: "b")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-456/analytics/chi-square"))
    }

    func testChiSquareWithGroupIds() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable_1": "a",
                "variable_2": "b",
                "chi_square_statistic": 5.0,
                "p_value": 0.05,
                "degrees_of_freedom": 2,
                "significant": true,
            ])
        ]

        _ = try await analyticsClient.chiSquare(
            variable1: "a",
            variable2: "b",
            groupIds: ["g1", "g2", "g3"],
            confidenceLevel: 0.99
        )

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["group_ids"] as? [String], ["g1", "g2", "g3"])
        XCTAssertEqual(body["confidence_level"] as? Double, 0.99)
    }

    // MARK: - ANOVA

    func testAnovaReturnsDecodedResult() async throws {
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

        let result = try await analyticsClient.anova(variable: "latency")

        XCTAssertEqual(result.variable, "latency")
        XCTAssertEqual(result.groupBy, "device_group")
        XCTAssertEqual(result.fStatistic, 5.67)
        XCTAssertEqual(result.pValue, 0.004)
        XCTAssertEqual(result.degreesOfFreedomBetween, 2)
        XCTAssertEqual(result.degreesOfFreedomWithin, 97)
        XCTAssertTrue(result.significant)
        XCTAssertEqual(result.postHocPairs?.count, 2)
        XCTAssertEqual(result.postHocPairs?[0].groupA, "g1")
        XCTAssertEqual(result.postHocPairs?[0].groupB, "g2")
        XCTAssertTrue(result.postHocPairs?[0].significant ?? false)
        XCTAssertFalse(result.postHocPairs?[1].significant ?? true)
    }

    func testAnovaSendsCorrectEndpoint() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "x",
                "group_by": "device_group",
                "f_statistic": 0.0,
                "p_value": 1.0,
                "degrees_of_freedom_between": 1,
                "degrees_of_freedom_within": 10,
                "significant": false,
            ])
        ]

        _ = try await analyticsClient.anova(variable: "x")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-456/analytics/anova"))
    }

    func testAnovaWithAllParameters() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "variable": "loss",
                "group_by": "federation_member",
                "f_statistic": 3.2,
                "p_value": 0.04,
                "degrees_of_freedom_between": 3,
                "degrees_of_freedom_within": 50,
                "significant": true,
            ])
        ]

        _ = try await analyticsClient.anova(
            variable: "loss",
            groupBy: "federation_member",
            groupIds: ["m1", "m2"],
            confidenceLevel: 0.99,
            postHoc: false
        )

        let body = try JSONSerialization.jsonObject(
            with: SharedMockURLProtocol.requests.last!.httpBody!
        ) as! [String: Any]
        XCTAssertEqual(body["variable"] as? String, "loss")
        XCTAssertEqual(body["group_by"] as? String, "federation_member")
        XCTAssertEqual(body["group_ids"] as? [String], ["m1", "m2"])
        XCTAssertEqual(body["confidence_level"] as? Double, 0.99)
        XCTAssertEqual(body["post_hoc"] as? Bool, false)
    }

    // MARK: - List Queries

    func testListQueriesReturnsDecodedResult() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "queries": [
                    [
                        "id": "q1",
                        "federation_id": "fed-456",
                        "query_type": "descriptive",
                        "variable": "accuracy",
                        "group_by": "device_group",
                        "status": "completed",
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-01T00:00:01Z",
                    ],
                    [
                        "id": "q2",
                        "federation_id": "fed-456",
                        "query_type": "t_test",
                        "variable": "loss",
                        "group_by": "device_group",
                        "status": "pending",
                        "created_at": "2026-01-02T00:00:00Z",
                        "updated_at": "2026-01-02T00:00:00Z",
                    ],
                ],
                "total": 2,
            ])
        ]

        let result = try await analyticsClient.listQueries(limit: 25, offset: 0)

        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(result.queries.count, 2)
        XCTAssertEqual(result.queries[0].id, "q1")
        XCTAssertEqual(result.queries[0].queryType, "descriptive")
        XCTAssertEqual(result.queries[0].status, "completed")
        XCTAssertEqual(result.queries[1].id, "q2")
        XCTAssertEqual(result.queries[1].status, "pending")
    }

    func testListQueriesSendsCorrectEndpoint() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "queries": [],
                "total": 0,
            ])
        ]

        _ = try await analyticsClient.listQueries(limit: 10, offset: 5)

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-456/analytics/queries"))

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let limitParam = components.queryItems?.first { $0.name == "limit" }
        let offsetParam = components.queryItems?.first { $0.name == "offset" }
        XCTAssertEqual(limitParam?.value, "10")
        XCTAssertEqual(offsetParam?.value, "5")
    }

    func testListQueriesDefaultParameters() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "queries": [],
                "total": 0,
            ])
        ]

        _ = try await analyticsClient.listQueries()

        let request = SharedMockURLProtocol.requests.last!
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let limitParam = components.queryItems?.first { $0.name == "limit" }
        let offsetParam = components.queryItems?.first { $0.name == "offset" }
        XCTAssertEqual(limitParam?.value, "50")
        XCTAssertEqual(offsetParam?.value, "0")
    }

    // MARK: - Get Query

    func testGetQueryReturnsDecodedResult() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "id": "q42",
                "federation_id": "fed-456",
                "query_type": "anova",
                "variable": "latency",
                "group_by": "federation_member",
                "status": "completed",
                "error_message": NSNull(),
                "created_at": "2026-02-15T10:00:00Z",
                "updated_at": "2026-02-15T10:00:05Z",
            ])
        ]

        let result = try await analyticsClient.getQuery(queryId: "q42")

        XCTAssertEqual(result.id, "q42")
        XCTAssertEqual(result.federationId, "fed-456")
        XCTAssertEqual(result.queryType, "anova")
        XCTAssertEqual(result.variable, "latency")
        XCTAssertEqual(result.groupBy, "federation_member")
        XCTAssertEqual(result.status, "completed")
        XCTAssertNil(result.errorMessage)
    }

    func testGetQuerySendsCorrectEndpoint() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "id": "q42",
                "federation_id": "fed-456",
                "query_type": "t_test",
                "variable": "x",
                "group_by": "device_group",
                "status": "completed",
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:00Z",
            ])
        ]

        _ = try await analyticsClient.getQuery(queryId: "q42")

        let request = SharedMockURLProtocol.requests.last!
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url!.path.contains("/federations/fed-456/analytics/queries/q42"))
    }

    // MARK: - Error Handling

    func testServerErrorThrows() async throws {
        await setUpToken()
        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["detail": "Internal server error"])
        ]

        do {
            _ = try await analyticsClient.descriptive(variable: "x")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected server error
            XCTAssertTrue(error is OctomilError)
        }
    }

    func testMissingTokenThrows() async throws {
        // Don't set token
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: ["variable": "x", "group_by": "device_group", "groups": []])
        ]

        do {
            _ = try await analyticsClient.descriptive(variable: "x")
            XCTFail("Expected authentication error")
        } catch {
            XCTAssertTrue(error is OctomilError)
        }
    }

    // MARK: - OctomilClient Factory

    func testOctomilClientAnalyticsFactory() {
        let client = OctomilClient(
            deviceAccessToken: "test-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        let analytics = client.analytics(federationId: "fed-abc")
        XCTAssertNotNil(analytics)
    }

    func testOctomilClientAnalyticsFactoryCreatesSeparateInstances() {
        let client = OctomilClient(
            deviceAccessToken: "test-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        let analytics1 = client.analytics(federationId: "fed-1")
        let analytics2 = client.analytics(federationId: "fed-2")

        // Each call returns a new instance (different federation)
        XCTAssertFalse(analytics1 === analytics2)
    }

    // MARK: - Codable Models

    func testAnalyticsFilterEncodesSnakeCase() throws {
        let filter = AnalyticsFilter(
            startTime: "2026-01-01T00:00:00Z",
            endTime: "2026-02-01T00:00:00Z",
            devicePlatform: "ios",
            minSampleCount: 50
        )

        let data = try JSONEncoder().encode(filter)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["start_time"] as? String, "2026-01-01T00:00:00Z")
        XCTAssertEqual(json["end_time"] as? String, "2026-02-01T00:00:00Z")
        XCTAssertEqual(json["device_platform"] as? String, "ios")
        XCTAssertEqual(json["min_sample_count"] as? Int, 50)
    }

    func testAnalyticsFilterRoundTrip() throws {
        let filter = AnalyticsFilter(
            startTime: "2026-01-01T00:00:00Z",
            devicePlatform: "android"
        )

        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(AnalyticsFilter.self, from: data)

        XCTAssertEqual(decoded.startTime, filter.startTime)
        XCTAssertEqual(decoded.devicePlatform, filter.devicePlatform)
        XCTAssertNil(decoded.endTime)
        XCTAssertNil(decoded.minSampleCount)
    }

    func testDescriptiveResultDecodesFromJSON() throws {
        let json = """
        {
            "variable": "accuracy",
            "group_by": "device_group",
            "groups": [{
                "group_id": "g1",
                "count": 50,
                "mean": 0.9,
                "percentiles": {"p50": 0.91, "p95": 0.98}
            }]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(DescriptiveResult.self, from: json)

        XCTAssertEqual(result.variable, "accuracy")
        XCTAssertEqual(result.groups[0].percentiles?["p50"], 0.91)
        XCTAssertEqual(result.groups[0].percentiles?["p95"], 0.98)
        XCTAssertNil(result.groups[0].median)
        XCTAssertNil(result.groups[0].stdDev)
    }

    func testTTestResultDecodesWithoutConfidenceInterval() throws {
        let json = """
        {
            "variable": "x",
            "group_a": "a",
            "group_b": "b",
            "t_statistic": 1.5,
            "p_value": 0.13,
            "degrees_of_freedom": 20.0,
            "significant": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(TTestResult.self, from: json)

        XCTAssertNil(result.confidenceInterval)
        XCTAssertFalse(result.significant)
    }

    func testChiSquareResultDecodesWithoutCramersV() throws {
        let json = """
        {
            "variable_1": "a",
            "variable_2": "b",
            "chi_square_statistic": 3.0,
            "p_value": 0.08,
            "degrees_of_freedom": 1,
            "significant": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(ChiSquareResult.self, from: json)

        XCTAssertNil(result.cramersV)
        XCTAssertFalse(result.significant)
    }

    func testAnovaResultDecodesWithoutPostHoc() throws {
        let json = """
        {
            "variable": "latency",
            "group_by": "device_group",
            "f_statistic": 2.1,
            "p_value": 0.12,
            "degrees_of_freedom_between": 2,
            "degrees_of_freedom_within": 47,
            "significant": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AnovaResult.self, from: json)

        XCTAssertNil(result.postHocPairs)
        XCTAssertFalse(result.significant)
    }

    func testPostHocPairDecoding() throws {
        let json = """
        {
            "group_a": "control",
            "group_b": "treatment",
            "p_value": 0.001,
            "significant": true
        }
        """.data(using: .utf8)!

        let pair = try JSONDecoder().decode(PostHocPair.self, from: json)

        XCTAssertEqual(pair.groupA, "control")
        XCTAssertEqual(pair.groupB, "treatment")
        XCTAssertEqual(pair.pValue, 0.001)
        XCTAssertTrue(pair.significant)
    }

    func testAnalyticsQueryDecodesWithErrorMessage() throws {
        let json = """
        {
            "id": "q-err",
            "federation_id": "fed-456",
            "query_type": "descriptive",
            "variable": "x",
            "group_by": "device_group",
            "status": "failed",
            "error_message": "Insufficient data",
            "created_at": "2026-02-28T00:00:00Z",
            "updated_at": "2026-02-28T00:00:01Z"
        }
        """.data(using: .utf8)!

        let query = try JSONDecoder().decode(AnalyticsQuery.self, from: json)

        XCTAssertEqual(query.id, "q-err")
        XCTAssertEqual(query.status, "failed")
        XCTAssertEqual(query.errorMessage, "Insufficient data")
    }
}

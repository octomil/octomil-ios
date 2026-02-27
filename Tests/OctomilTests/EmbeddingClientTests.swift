import Foundation
import XCTest
@testable import Octomil

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class EmbeddingClientTests: XCTestCase {

    private var client: EmbeddingClient!

    override func setUp() {
        super.setUp()
        SharedMockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedMockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = EmbeddingClient(
            serverURL: URL(string: "https://api.octomil.com")!,
            apiKey: "test-key",
            session: session
        )
    }

    override func tearDown() {
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - EmbeddingUsage

    func testEmbeddingUsageCodable() throws {
        let usage = EmbeddingUsage(promptTokens: 5, totalTokens: 5)
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(EmbeddingUsage.self, from: data)
        XCTAssertEqual(decoded.promptTokens, 5)
        XCTAssertEqual(decoded.totalTokens, 5)
    }

    func testEmbeddingUsageCodingKeys() throws {
        let usage = EmbeddingUsage(promptTokens: 3, totalTokens: 7)
        let data = try JSONEncoder().encode(usage)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["prompt_tokens"])
        XCTAssertNotNil(json["total_tokens"])
    }

    // MARK: - EmbeddingResult

    func testEmbeddingResultFields() {
        let result = EmbeddingResult(
            embeddings: [[0.1, 0.2], [0.3, 0.4]],
            model: "nomic-embed-text",
            usage: EmbeddingUsage(promptTokens: 10, totalTokens: 10)
        )
        XCTAssertEqual(result.embeddings.count, 2)
        XCTAssertEqual(result.model, "nomic-embed-text")
        XCTAssertEqual(result.usage.promptTokens, 10)
    }

    // MARK: - Single string embed

    func testEmbedSingleString() async throws {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "data": [
                    ["embedding": [0.1, 0.2, 0.3], "index": 0]
                ],
                "model": "nomic-embed-text",
                "usage": ["prompt_tokens": 5, "total_tokens": 5],
            ])
        ]

        let result = try await client.embed(modelId: "nomic-embed-text", input: "hello world")

        XCTAssertEqual(result.embeddings.count, 1)
        XCTAssertEqual(result.embeddings[0], [0.1, 0.2, 0.3])
        XCTAssertEqual(result.model, "nomic-embed-text")
        XCTAssertEqual(result.usage.promptTokens, 5)
        XCTAssertEqual(result.usage.totalTokens, 5)
    }

    // MARK: - Multiple strings embed

    func testEmbedMultipleStrings() async throws {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "data": [
                    ["embedding": [0.1, 0.2], "index": 0],
                    ["embedding": [0.3, 0.4], "index": 1],
                ],
                "model": "nomic-embed-text",
                "usage": ["prompt_tokens": 10, "total_tokens": 10],
            ])
        ]

        let result = try await client.embed(modelId: "nomic-embed-text", input: ["hello", "world"])

        XCTAssertEqual(result.embeddings.count, 2)
        XCTAssertEqual(result.embeddings[0], [0.1, 0.2])
        XCTAssertEqual(result.embeddings[1], [0.3, 0.4])
    }

    // MARK: - Request format

    func testRequestFormat() async throws {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "data": [["embedding": [0.1], "index": 0]],
                "model": "nomic-embed-text",
                "usage": ["prompt_tokens": 1, "total_tokens": 1],
            ])
        ]

        _ = try await client.embed(modelId: "nomic-embed-text", input: "test")

        let request = try XCTUnwrap(SharedMockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.octomil.com/api/v1/embeddings")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model_id"] as? String, "nomic-embed-text")
        XCTAssertEqual(json["input"] as? String, "test")
    }

    // MARK: - Error handling

    func testHTTPErrorThrows() async {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 401, json: ["error": "unauthorized"])
        ]

        do {
            _ = try await client.embed(modelId: "model", input: "test")
            XCTFail("Expected error to be thrown")
        } catch let error as OctomilError {
            if case .serverError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 401)
            } else {
                XCTFail("Expected serverError, got: \(error)")
            }
        } catch {
            XCTFail("Expected OctomilError, got: \(error)")
        }
    }

    // MARK: - Missing usage defaults

    func testMissingUsageDefaults() async throws {
        SharedMockURLProtocol.responses = [
            .success(statusCode: 200, json: [
                "data": [["embedding": [0.1], "index": 0]],
                "model": "nomic-embed-text",
            ])
        ]

        let result = try await client.embed(modelId: "nomic-embed-text", input: "test")
        XCTAssertEqual(result.usage.promptTokens, 0)
        XCTAssertEqual(result.usage.totalTokens, 0)
    }
}

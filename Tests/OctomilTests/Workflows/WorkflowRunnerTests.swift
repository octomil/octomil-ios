import XCTest
@testable import Octomil

final class WorkflowRunnerTests: XCTestCase {

    func testSingleInferenceStep() async throws {
        let runtime = WorkflowMockRuntime(responses: [
            RuntimeResponse(text: "inference output"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let runner = WorkflowRunner(responses: responses)

        let workflow = Workflow(name: "single", steps: [
            .inference(model: "test-model"),
        ])

        let result = try await runner.run(workflow: workflow, input: "Hello")

        XCTAssertEqual(result.outputs.count, 1)
        if case .text(let text) = result.outputs[0].output.first {
            XCTAssertEqual(text, "inference output")
        } else {
            XCTFail("Expected text output")
        }
        XCTAssertGreaterThanOrEqual(result.totalLatencyMs, 0)
    }

    func testMultiStepPipeline() async throws {
        let runtime = WorkflowMockRuntime(responses: [
            RuntimeResponse(text: "step1 output"),
            RuntimeResponse(text: "step3 output"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let runner = WorkflowRunner(responses: responses)

        let workflow = Workflow(name: "pipeline", steps: [
            .inference(model: "model-a"),
            .transform(name: "uppercase", transform: { $0.uppercased() }),
            .inference(model: "model-b"),
        ])

        let result = try await runner.run(workflow: workflow, input: "start")

        XCTAssertEqual(result.outputs.count, 2)

        // The transform step doesn't produce a Response, so we have 2 outputs
        if case .text(let text1) = result.outputs[0].output.first {
            XCTAssertEqual(text1, "step1 output")
        } else {
            XCTFail("Expected text output from step 1")
        }

        // Verify the second inference received the uppercased output from transform
        XCTAssertNotNil(runtime.capturedPrompts.last)
        XCTAssertTrue(runtime.capturedPrompts.last!.contains("STEP1 OUTPUT"))
    }

    func testToolRoundStep() async throws {
        let runtime = WorkflowSequentialToolRuntime(responses: [
            // Tool call response
            RuntimeResponse(
                text: "",
                toolCalls: [RuntimeToolCall(id: "call_1", name: "lookup", arguments: "{}")]
            ),
            // Final text response after tool result
            RuntimeResponse(text: "tool round complete"),
        ])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let executor = WorkflowMockExecutor(results: ["lookup": "found it"])
        let runner = WorkflowRunner(responses: responses, executor: executor)

        let workflow = Workflow(name: "tool-workflow", steps: [
            .toolRound(
                tools: [Tool.function(name: "lookup", description: "Look up data")],
                model: "test-model",
                maxIterations: 3
            ),
        ])

        let result = try await runner.run(workflow: workflow, input: "find something")

        XCTAssertEqual(result.outputs.count, 1)
        if case .text(let text) = result.outputs[0].output.first {
            XCTAssertEqual(text, "tool round complete")
        } else {
            XCTFail("Expected text output")
        }
    }

    func testEmptyWorkflowReturnsEmptyResult() async throws {
        let responses = OctomilResponses(runtimeResolver: { _ in
            WorkflowMockRuntime(responses: [])
        })
        let runner = WorkflowRunner(responses: responses)

        let workflow = Workflow(name: "empty", steps: [])

        let result = try await runner.run(workflow: workflow, input: "ignored")

        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertGreaterThanOrEqual(result.totalLatencyMs, 0)
    }

    func testToolRoundThrowsWithoutExecutor() async throws {
        let runtime = WorkflowMockRuntime(responses: [])
        let responses = OctomilResponses(runtimeResolver: { _ in runtime })
        let runner = WorkflowRunner(responses: responses, executor: nil)

        let workflow = Workflow(name: "no-executor", steps: [
            .toolRound(
                tools: [Tool.function(name: "test", description: "test")],
                model: "test-model"
            ),
        ])

        do {
            _ = try await runner.run(workflow: workflow, input: "hello")
            XCTFail("Should have thrown WorkflowError.missingExecutor")
        } catch is WorkflowError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Test Helpers

private final class WorkflowMockRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    private var responses: [RuntimeResponse]
    private var index = 0
    var capturedPrompts: [String] = []

    init(responses: [RuntimeResponse]) { self.responses = responses }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        capturedPrompts.append(request.prompt)
        guard index < responses.count else { return RuntimeResponse(text: "") }
        let response = responses[index]
        index += 1
        return response
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class WorkflowSequentialToolRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    private var responses: [RuntimeResponse]
    private var index = 0

    init(responses: [RuntimeResponse]) { self.responses = responses }

    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        guard index < responses.count else { return RuntimeResponse(text: "") }
        let response = responses[index]
        index += 1
        return response
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}

private final class WorkflowMockExecutor: ToolExecutor, @unchecked Sendable {
    let results: [String: String]
    init(results: [String: String]) { self.results = results }
    func execute(call: ResponseToolCall) async throws -> ToolResult {
        ToolResult(toolCallId: call.id, content: results[call.name] ?? "unknown")
    }
}

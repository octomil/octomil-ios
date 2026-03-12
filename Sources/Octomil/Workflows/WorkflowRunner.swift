import Foundation

/// Executes a ``Workflow`` by running each step sequentially, threading
/// the text output of each step into the next.
public final class WorkflowRunner: @unchecked Sendable {
    private let responses: OctomilResponses
    private let executor: ToolExecutor?

    public init(responses: OctomilResponses, executor: ToolExecutor? = nil) {
        self.responses = responses
        self.executor = executor
    }

    public func run(workflow: Workflow, input: String) async throws -> WorkflowResult {
        let startTime = DispatchTime.now()
        var currentText = input
        var outputs: [Response] = []

        for step in workflow.steps {
            switch step {
            case .inference(let model, let instructions, let maxOutputTokens):
                let request = ResponseRequest(
                    model: model,
                    input: [.text(currentText)],
                    maxOutputTokens: maxOutputTokens,
                    instructions: instructions
                )
                let response = try await responses.create(request)
                outputs.append(response)
                currentText = extractText(from: response)

            case .toolRound(let tools, let model, let maxIterations):
                guard let executor = executor else {
                    throw WorkflowError.missingExecutor
                }
                let runner = ToolRunner(responses: responses, executor: executor, maxIterations: maxIterations)
                let request = ResponseRequest(
                    model: model,
                    input: [.text(currentText)],
                    tools: tools
                )
                let response = try await runner.run(request)
                outputs.append(response)
                currentText = extractText(from: response)

            case .transform(_, let transform):
                currentText = try await transform(currentText)
            }
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let totalLatencyMs = Int64(elapsed / 1_000_000)
        return WorkflowResult(outputs: outputs, totalLatencyMs: totalLatencyMs)
    }

    private func extractText(from response: Response) -> String {
        response.output.compactMap { item -> String? in
            if case .text(let text) = item { return text }
            return nil
        }.joined()
    }
}

/// Errors specific to workflow execution.
public enum WorkflowError: Error {
    case missingExecutor
}

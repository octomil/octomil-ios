import Foundation

/// Convenience loop that runs model -> tool calls -> execute -> feed results -> repeat.
///
/// Continues until the model produces a text response (no tool calls) or
/// ``maxIterations`` is reached.
///
/// ```swift
/// let runner = ToolRunner(responses: responses, executor: myExecutor)
/// let response = try await runner.run(
///     ResponseRequest(model: "phi-4-mini", input: [.text("What's the weather?")], tools: [...])
/// )
/// ```
public final class ToolRunner: @unchecked Sendable {
    private let responses: OctomilResponses
    private let executor: ToolExecutor
    private let maxIterations: Int

    public init(responses: OctomilResponses, executor: ToolExecutor, maxIterations: Int = 10) {
        self.responses = responses
        self.executor = executor
        self.maxIterations = maxIterations
    }

    public func run(_ request: ResponseRequest) async throws -> Response {
        var currentInput = request.input
        var iteration = 0

        while iteration < maxIterations {
            let currentRequest = ResponseRequest(
                model: request.model,
                input: currentInput,
                tools: request.tools,
                toolChoice: request.toolChoice,
                responseFormat: request.responseFormat,
                maxOutputTokens: request.maxOutputTokens,
                temperature: request.temperature,
                topP: request.topP,
                stop: request.stop,
                metadata: request.metadata
            )
            let response = try await responses.create(currentRequest)

            let toolCalls = response.output.compactMap { item -> ResponseToolCall? in
                if case .toolCall(let call) = item { return call }
                return nil
            }

            if toolCalls.isEmpty {
                return response
            }

            // Add assistant message with tool calls
            currentInput.append(.assistant(content: nil, toolCalls: toolCalls))

            // Execute each tool call and add results
            for call in toolCalls {
                let result: ToolResult
                do {
                    result = try await executor.execute(call: call)
                } catch {
                    result = ToolResult(
                        toolCallId: call.id,
                        content: "Error: \(error.localizedDescription)",
                        isError: true
                    )
                }
                currentInput.append(.toolResult(toolCallId: result.toolCallId, content: result.content))
            }

            iteration += 1
        }

        // Max iterations reached — make a final call without tools
        let finalRequest = ResponseRequest(
            model: request.model,
            input: currentInput,
            tools: [],
            maxOutputTokens: request.maxOutputTokens,
            temperature: request.temperature,
            topP: request.topP,
            stop: request.stop,
            metadata: request.metadata
        )
        return try await responses.create(finalRequest)
    }
}

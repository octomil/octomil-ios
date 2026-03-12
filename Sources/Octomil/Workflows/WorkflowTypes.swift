import Foundation

/// A named sequence of inference and transformation steps.
public struct Workflow: @unchecked Sendable {
    public let name: String
    public let steps: [WorkflowStep]

    public init(name: String, steps: [WorkflowStep]) {
        self.name = name
        self.steps = steps
    }
}

/// A single step in a ``Workflow``.
public enum WorkflowStep: @unchecked Sendable {
    /// Run inference with the given model and optional instructions.
    case inference(model: String, instructions: String? = nil, maxOutputTokens: Int? = nil)

    /// Run a tool-use loop with the given tools and model.
    case toolRound(tools: [Tool], model: String, maxIterations: Int = 5)

    /// Apply a custom transformation to the current text.
    case transform(name: String, transform: @Sendable (String) async throws -> String)
}

/// The result of executing a ``Workflow``.
public struct WorkflowResult: Sendable {
    public let outputs: [Response]
    public let totalLatencyMs: Int64

    public init(outputs: [Response], totalLatencyMs: Int64) {
        self.outputs = outputs
        self.totalLatencyMs = totalLatencyMs
    }
}

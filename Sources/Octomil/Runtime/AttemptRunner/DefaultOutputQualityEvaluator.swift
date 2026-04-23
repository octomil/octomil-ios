import Foundation

/// Built-in SDK-local output quality evaluator.
///
/// Evaluators run in-process and return only privacy-safe metadata. They never
/// upload prompt, output, or message content.
public struct DefaultOutputQualityEvaluator: OutputQualityGateEvaluator {
    public let name = "default_output_quality"

    public init() {}

    public func evaluate(gate: CandidateGate, response: Any) async -> GateEvaluationResult {
        switch gate.code {
        case GateCode.jsonParseable.rawValue, GateCode.schemaValid.rawValue:
            return evaluateJSON(response: response)
        case GateCode.toolCallValid.rawValue:
            return evaluateToolCalls(response: response)
        case GateCode.evaluatorScoreMin.rawValue:
            return evaluateRegex(gate: gate, response: response)
        case GateCode.safetyPassed.rawValue:
            return GateEvaluationResult(
                passed: false,
                reasonCode: "no_safety_checker_configured",
                safeMetadata: ["evaluator_name": name]
            )
        case GateCode.maxRefusalRate.rawValue:
            return evaluateRefusal(response: response)
        default:
            return GateEvaluationResult(
                passed: false,
                reasonCode: "evaluator_missing",
                safeMetadata: ["evaluator_name": name]
            )
        }
    }

    private func evaluateJSON(response: Any) -> GateEvaluationResult {
        guard let text = extractText(response), let data = text.data(using: .utf8) else {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "no_text_content",
                safeMetadata: ["evaluator_name": name]
            )
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return GateEvaluationResult(passed: true, safeMetadata: ["evaluator_name": name])
        } catch {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "json_parse_error",
                safeMetadata: ["evaluator_name": name, "error_type": String(describing: type(of: error))]
            )
        }
    }

    private func evaluateToolCalls(response: Any) -> GateEvaluationResult {
        let calls = extractToolCalls(response)
        guard !calls.isEmpty else {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "no_tool_calls",
                safeMetadata: ["evaluator_name": name]
            )
        }
        for call in calls {
            guard !call.name.isEmpty else {
                return GateEvaluationResult(
                    passed: false,
                    reasonCode: "tool_call_missing_name",
                    safeMetadata: ["evaluator_name": name]
                )
            }
            guard let data = call.arguments.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                return GateEvaluationResult(
                    passed: false,
                    reasonCode: "tool_call_invalid_arguments",
                    safeMetadata: ["evaluator_name": name]
                )
            }
        }
        return GateEvaluationResult(passed: true, safeMetadata: ["evaluator_name": name])
    }

    private func evaluateRegex(gate: CandidateGate, response: Any) -> GateEvaluationResult {
        guard let pattern = gate.thresholdString, !pattern.isEmpty else {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "no_pattern_configured",
                safeMetadata: ["evaluator_name": name]
            )
        }
        guard let text = extractText(response) else {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "no_text_content",
                safeMetadata: ["evaluator_name": name]
            )
        }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matched = regex.firstMatch(in: text, range: range) != nil
            return GateEvaluationResult(
                passed: matched,
                score: matched ? 1.0 : 0.0,
                reasonCode: matched ? nil : "pattern_not_matched",
                safeMetadata: ["evaluator_name": name]
            )
        } catch {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "invalid_regex_pattern",
                safeMetadata: ["evaluator_name": name]
            )
        }
    }

    private func evaluateRefusal(response: Any) -> GateEvaluationResult {
        guard let text = extractText(response)?.lowercased() else {
            return GateEvaluationResult(
                passed: false,
                reasonCode: "no_text_content",
                safeMetadata: ["evaluator_name": name]
            )
        }
        let refusalMarkers = [
            "i can't",
            "i cannot",
            "i'm unable",
            "i am unable",
            "sorry, but",
        ]
        let refused = refusalMarkers.contains { text.contains($0) }
        return GateEvaluationResult(
            passed: !refused,
            score: refused ? 0.0 : 1.0,
            reasonCode: refused ? "refusal_detected" : nil,
            safeMetadata: ["evaluator_name": name]
        )
    }

    private func extractText(_ response: Any) -> String? {
        if let text = response as? String {
            return text
        }
        if let runtimeResponse = response as? RuntimeResponse {
            return runtimeResponse.text
        }
        if let sdkResponse = response as? Response {
            return sdkResponse.outputText
        }
        return nil
    }

    private func extractToolCalls(_ response: Any) -> [RuntimeToolCall] {
        if let runtimeResponse = response as? RuntimeResponse {
            return runtimeResponse.toolCalls ?? []
        }
        if let sdkResponse = response as? Response {
            return sdkResponse.output.compactMap { item in
                if case .toolCall(let call) = item {
                    return RuntimeToolCall(id: call.id, name: call.name, arguments: call.arguments)
                }
                return nil
            }
        }
        return []
    }
}

import Foundation

/// Formats ``InputItem``s and tools into a ChatML-style prompt string.
///
/// Reuses the same template format as ``OctomilChat/formatPrompt(_:)``.
public enum PromptFormatter {

    public static func format(
        input: [InputItem],
        tools: [Tool] = [],
        toolChoice: ToolChoice = .auto
    ) -> String {
        var sb = ""

        // Add tool definitions as a system prompt if present
        if !tools.isEmpty {
            if case .none = toolChoice {
                // Skip tools when choice is .none
            } else {
                sb += "<|system|>\nYou have access to the following tools:\n\n"
                for tool in tools {
                    sb += "Function: \(tool.function.name)\n"
                    sb += "Description: \(tool.function.description)\n"
                    sb += "\n"
                }
                sb += "To use a tool, respond with JSON: {\"tool_call\": {\"name\": \"function_name\", \"arguments\": {...}}}\n"

                switch toolChoice {
                case .required:
                    sb += "You MUST use one of the available tools.\n"
                case .specific(let name):
                    sb += "You MUST use the tool: \(name)\n"
                default:
                    break
                }
                sb += "\n"
            }
        }

        // Format each input item
        for item in input {
            switch item {
            case .system(let content):
                sb += "<|system|>\n\(content)\n"

            case .user(let parts):
                sb += "<|user|>\n"
                for part in parts {
                    switch part {
                    case .text(let text):
                        sb += text
                    case .image:
                        sb += "[image]"
                    case .audio:
                        sb += "[audio]"
                    case .file(_, _, let filename):
                        sb += "[file: \(filename ?? "attachment")]"
                    }
                }
                sb += "\n"

            case .assistant(let content, let toolCalls):
                sb += "<|assistant|>\n"
                if let content = content {
                    for part in content {
                        if case .text(let text) = part {
                            sb += text
                        }
                    }
                }
                if let toolCalls = toolCalls {
                    for call in toolCalls {
                        sb += "{\"tool_call\": {\"name\": \"\(call.name)\", \"arguments\": \(call.arguments)}}"
                    }
                }
                sb += "\n"

            case .toolResult(_, let content):
                sb += "<|tool|>\n\(content)\n"
            }
        }

        sb += "<|assistant|>\n"
        return sb
    }
}

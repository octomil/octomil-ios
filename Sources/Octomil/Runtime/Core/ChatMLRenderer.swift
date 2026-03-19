import Foundation

/// Canonical ChatML renderer for text-only engines.
public enum ChatMLRenderer {
    public static func render(
        _ request: RuntimeRequest,
        toolChoice: String = "auto",
        specificToolName: String? = nil
    ) -> String {
        var sb = ""

        // Tool definitions block
        if let tools = request.toolDefinitions, !tools.isEmpty, toolChoice != "none" {
            sb += renderToolBlock(tools, toolChoice: toolChoice, specificToolName: specificToolName)
        }

        // Messages
        for msg in request.messages {
            sb += renderMessage(msg)
        }

        // Generation prompt
        sb += "<|assistant|>\n"
        return sb
    }

    private static func renderToolBlock(_ tools: [RuntimeToolDef], toolChoice: String, specificToolName: String?) -> String {
        var sb = "<|system|>\nYou have access to the following tools:\n\n"
        for tool in tools {
            sb += "Function: \(tool.name)\n"
            sb += "Description: \(tool.description)\n"
            if let schema = tool.parametersSchema {
                sb += "Parameters: \(schema)\n"
            }
            sb += "\n"
        }
        sb += "To use a tool, respond with ONLY this JSON and nothing else:\n"
        sb += "{\"type\": \"tool_call\", \"name\": \"function_name\", \"arguments\": {...}}\n"
        sb += "If you do not need a tool, respond with normal text.\n"
        if toolChoice == "required" {
            sb += "You MUST use one of the available tools.\n"
        } else if toolChoice == "specific", let name = specificToolName {
            sb += "You MUST use the tool: \(name)\n"
        }
        sb += "\n"
        return sb
    }

    private static func renderMessage(_ msg: RuntimeMessage) -> String {
        var sb = "<|\(msg.role.rawValue)|>\n"
        var prevWasText = false
        for part in msg.parts {
            switch part {
            case .text(let text):
                if prevWasText { sb += "\n" }
                sb += text
                prevWasText = true
            case .image:
                sb += "[image]"
                prevWasText = false
            case .audio:
                sb += "[audio]"
                prevWasText = false
            case .video:
                sb += "[video]"
                prevWasText = false
            }
        }
        sb += "\n"
        return sb
    }
}

import XCTest
@testable import Octomil

final class PromptFormatterTests: XCTestCase {

    func testFormatsSimpleTextInput() {
        let result = PromptFormatter.format(input: [.text("Hello")])
        XCTAssertTrue(result.contains("<|user|>\nHello\n"))
        XCTAssertTrue(result.hasSuffix("<|assistant|>\n"))
    }

    func testFormatsSystemMessage() {
        let result = PromptFormatter.format(input: [
            .system("You are helpful"),
            .text("Hi"),
        ])
        XCTAssertTrue(result.contains("<|system|>\nYou are helpful\n"))
        XCTAssertTrue(result.contains("<|user|>\nHi\n"))
    }

    func testFormatsToolResult() {
        let result = PromptFormatter.format(input: [
            .toolResult(toolCallId: "call_1", content: "72\u{00B0}F"),
        ])
        XCTAssertTrue(result.contains("<|tool|>\n72\u{00B0}F\n"))
    }

    func testFormatsAssistantWithToolCalls() {
        let result = PromptFormatter.format(input: [
            .assistant(
                content: nil,
                toolCalls: [ResponseToolCall(id: "call_1", name: "get_weather", arguments: "{\"city\":\"NYC\"}")]
            ),
        ])
        XCTAssertTrue(result.contains("<|assistant|>\n"))
        XCTAssertTrue(result.contains("get_weather"))
    }

    func testIncludesToolDefinitions() {
        let result = PromptFormatter.format(
            input: [.text("What's the weather?")],
            tools: [Tool.function(name: "get_weather", description: "Get weather for a city")]
        )
        XCTAssertTrue(result.contains("Function: get_weather"))
        XCTAssertTrue(result.contains("Description: Get weather for a city"))
    }

    func testSkipsToolsWhenToolChoiceIsNone() {
        let result = PromptFormatter.format(
            input: [.text("Hello")],
            tools: [Tool.function(name: "get_weather", description: "Get weather")],
            toolChoice: .none
        )
        XCTAssertFalse(result.contains("Function: get_weather"))
    }

    func testAddsRequiredInstruction() {
        let result = PromptFormatter.format(
            input: [.text("Hello")],
            tools: [Tool.function(name: "get_weather", description: "Get weather")],
            toolChoice: .required
        )
        XCTAssertTrue(result.contains("MUST use one of the available tools"))
    }

    func testAddsSpecificToolInstruction() {
        let result = PromptFormatter.format(
            input: [.text("Hello")],
            tools: [Tool.function(name: "get_weather", description: "Get weather")],
            toolChoice: .specific("get_weather")
        )
        XCTAssertTrue(result.contains("MUST use the tool: get_weather"))
    }

    func testFormatsImagePlaceholder() {
        let result = PromptFormatter.format(input: [
            .user([
                .text("What is this?"),
                .imageData("base64data", mediaType: "image/png"),
            ]),
        ])
        XCTAssertTrue(result.contains("What is this?"))
        XCTAssertTrue(result.contains("[image]"))
    }

    func testFormatsMultiTurnConversation() {
        let result = PromptFormatter.format(input: [
            .system("You are a helpful assistant"),
            .text("Hello"),
            .assistant(content: [.text("Hi! How can I help?")], toolCalls: nil),
            .text("What is 2+2?"),
        ])
        XCTAssertTrue(result.contains("<|system|>\nYou are a helpful assistant\n"))
        XCTAssertTrue(result.contains("<|user|>\nHello\n"))
        XCTAssertTrue(result.contains("<|assistant|>\nHi! How can I help?\n"))
        XCTAssertTrue(result.contains("<|user|>\nWhat is 2+2?\n"))
        XCTAssertTrue(result.hasSuffix("<|assistant|>\n"))
    }
}

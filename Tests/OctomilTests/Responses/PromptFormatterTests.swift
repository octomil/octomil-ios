import XCTest
@testable import Octomil

final class ChatMLRendererTests: XCTestCase {

    func testRendersSimpleTextInput() {
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("<|user|>\nHello\n"))
        XCTAssertTrue(result.hasSuffix("<|assistant|>\n"))
    }

    func testRendersSystemMessage() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .system, parts: [.text("You are helpful")]),
                RuntimeMessage(role: .user, parts: [.text("Hi")]),
            ]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("<|system|>\nYou are helpful\n"))
        XCTAssertTrue(result.contains("<|user|>\nHi\n"))
    }

    func testRendersToolResult() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .tool, parts: [.text("72\u{00B0}F")]),
            ]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("<|tool|>\n72\u{00B0}F\n"))
    }

    func testRendersAssistantWithToolCalls() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .assistant, parts: [
                    .text("{\"tool_call\": {\"name\": \"get_weather\", \"arguments\": {\"city\":\"NYC\"}}}")
                ]),
            ]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("<|assistant|>\n"))
        XCTAssertTrue(result.contains("get_weather"))
    }

    func testIncludesToolDefinitions() {
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("What's the weather?")])],
            toolDefinitions: [
                RuntimeToolDef(name: "get_weather", description: "Get weather for a city"),
            ]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("Function: get_weather"))
        XCTAssertTrue(result.contains("Description: Get weather for a city"))
    }

    func testSkipsToolsWhenToolChoiceIsNone() {
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])],
            toolDefinitions: [
                RuntimeToolDef(name: "get_weather", description: "Get weather"),
            ]
        )
        let result = ChatMLRenderer.render(request, toolChoice: "none")
        XCTAssertFalse(result.contains("Function: get_weather"))
    }

    func testAddsRequiredInstruction() {
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])],
            toolDefinitions: [
                RuntimeToolDef(name: "get_weather", description: "Get weather"),
            ]
        )
        let result = ChatMLRenderer.render(request, toolChoice: "required")
        XCTAssertTrue(result.contains("MUST use one of the available tools"))
    }

    func testAddsSpecificToolInstruction() {
        let request = RuntimeRequest(
            messages: [RuntimeMessage(role: .user, parts: [.text("Hello")])],
            toolDefinitions: [
                RuntimeToolDef(name: "get_weather", description: "Get weather"),
            ]
        )
        let result = ChatMLRenderer.render(request, toolChoice: "specific", specificToolName: "get_weather")
        XCTAssertTrue(result.contains("MUST use the tool: get_weather"))
    }

    func testRendersImagePlaceholder() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .user, parts: [
                    .text("What is this?"),
                    .image(data: Data(), mediaType: "image/png"),
                ]),
            ]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("What is this?"))
        XCTAssertTrue(result.contains("[image]"))
    }

    func testRendersMultiTurnConversation() {
        let request = RuntimeRequest(
            messages: [
                RuntimeMessage(role: .system, parts: [.text("You are a helpful assistant")]),
                RuntimeMessage(role: .user, parts: [.text("Hello")]),
                RuntimeMessage(role: .assistant, parts: [.text("Hi! How can I help?")]),
                RuntimeMessage(role: .user, parts: [.text("What is 2+2?")]),
            ]
        )
        let result = ChatMLRenderer.render(request)
        XCTAssertTrue(result.contains("<|system|>\nYou are a helpful assistant\n"))
        XCTAssertTrue(result.contains("<|user|>\nHello\n"))
        XCTAssertTrue(result.contains("<|assistant|>\nHi! How can I help?\n"))
        XCTAssertTrue(result.contains("<|user|>\nWhat is 2+2?\n"))
        XCTAssertTrue(result.hasSuffix("<|assistant|>\n"))
    }
}

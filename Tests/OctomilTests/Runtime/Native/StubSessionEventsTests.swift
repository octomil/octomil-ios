import Foundation
import XCTest
@testable import Octomil

final class StubSessionEventsTests: XCTestCase {

    func testScriptedTimelineOrdering() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()

        var observed: [String] = []
        for try await event in await session.events(pollInterval: 0) {
            observed.append(Self.tag(for: event))
        }

        XCTAssertEqual(observed, [
            "started",
            "transcript", "transcript", "transcript",
            "turnEnded",
            "audio", "audio", "audio",
            "completed:ok",
        ])

        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testCancelSurfacesCancelledCompletion() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()

        // Drain the SESSION_STARTED + first transcript chunk, then cancel.
        _ = try await session.pollEvent(timeout: 0)
        _ = try await session.pollEvent(timeout: 0)
        try await session.cancel()

        let next = try await session.pollEvent(timeout: 0)
        guard case .sessionCompleted(let payload, _) = next else {
            XCTFail("Expected sessionCompleted, got \(String(describing: next))")
            return
        }
        XCTAssertEqual(payload.terminalStatus, .cancelled)

        // Subsequent polls return CANCELLED (mirrors C ABI).
        do {
            _ = try await session.pollEvent(timeout: 0)
            XCTFail("Expected NativeRuntimeError(.cancelled)")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .cancelled)
        }

        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testEventsStreamFinishesOnSessionCompleted() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()

        var count = 0
        for try await _ in await session.events(pollInterval: 0) {
            count += 1
        }
        // Default demo script has 9 events.
        XCTAssertEqual(count, 9)

        await session.close()
        try await model.close()
        await runtime.close()
    }

    // MARK: - Helpers

    private static func openSessionDefault() async throws -> (StubRuntime, any NativeModel, any NativeSession) {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        let session = try await runtime.openSession(
            config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
            model: model
        )
        return (runtime, model, session)
    }

    private static func tag(for event: NativeEvent) -> String {
        switch event {
        case .sessionStarted: return "started"
        case .transcriptChunk: return "transcript"
        case .turnEnded: return "turnEnded"
        case .audioChunk: return "audio"
        case .sessionCompleted(let payload, _): return "completed:\(payload.terminalStatus)"
        case .error: return "error"
        case .modelLoaded: return "modelLoaded"
        }
    }
}

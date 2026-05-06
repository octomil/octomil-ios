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

    func testEventsStreamCancelsViaTerminationOnConsumerCancel() async throws {
        // Empty script + pollInterval 0 forces the inner loop to spin on the
        // pollEvent-returns-nil → Task.yield() branch. Cancelling the consumer
        // task tears down the stream, which triggers `onTermination` →
        // task.cancel() → the inner while loop exits via Task.isCancelled.
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let anyModel = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        let stubModel = anyModel as! StubModel
        // Match openSession()'s borrow() so session.close() balances out.
        await stubModel.borrow()
        let session = StubSession(
            config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
            model: stubModel,
            artifactDigest: "sha256:test",
            script: []
        )

        let consumer = Task {
            var n = 0
            for try await _ in await session.events(pollInterval: 0) {
                n += 1
            }
            return n
        }

        // Let the producer spin on the nil/yield branch a few times, then cancel.
        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()
        _ = try? await consumer.value

        await session.close()
        try await stubModel.close()
        await runtime.close()
    }

    func testEventsStreamPropagatesPollErrors() async throws {
        // Drain a cancelled session past its terminal completion event so the
        // next pollEvent throws .cancelled. The events() wrapper must catch
        // that and finish(throwing:) — not silently swallow it.
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let anyModel = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        let stubModel = anyModel as! StubModel
        // Match openSession()'s borrow() so session.close() balances out.
        await stubModel.borrow()
        let session = StubSession(
            config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
            model: stubModel,
            artifactDigest: "sha256:test",
            script: []
        )
        try await session.cancel()
        // Drain the terminal completion event injected by cancel().
        _ = try await session.pollEvent(timeout: 0)

        do {
            for try await _ in await session.events(pollInterval: 0) {
                XCTFail("Cancelled session should not yield events")
            }
            XCTFail("Expected NativeRuntimeError(.cancelled)")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .cancelled)
        }

        await session.close()
        try await stubModel.close()
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

import Foundation
import XCTest
@testable import Octomil

final class StubRuntimeLifecycleTests: XCTestCase {

    // The runtime's `close()` precondition (open models present) traps
    // via `precondition`, which XCTest cannot catch. That guard is
    // verified by code review + manual smoke. The tests below cover the
    // happy path and the BUSY surfacing path that ARE testable.

    func testRuntimeCloseSucceedsAfterCascadeClose() async throws {
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

        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testModelCloseSurfacesBusyWhileSessionOpen() async throws {
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

        do {
            try await model.close()
            XCTFail("Expected NativeRuntimeError(.busy) — sessions still borrow the model")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .busy)
        }

        // After the session closes, model.close() should succeed.
        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testCapabilitiesReturnsHostInfo() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let caps = try await runtime.capabilities()
        XCTAssertTrue(caps.supportedEngines.contains("llama_cpp"))
        XCTAssertTrue(caps.supportedCapabilities.contains("asr.streaming"))
        XCTAssertTrue(caps.supportedArchs.contains("arm64"))
        XCTAssertGreaterThan(caps.ramTotalBytes, 0)
        XCTAssertGreaterThan(caps.ramAvailableBytes, 0)
        XCTAssertTrue(caps.hasAppleSilicon)
        XCTAssertTrue(caps.hasMetal)
        XCTAssertFalse(caps.hasCUDA)
        await runtime.close()
    }

    func testCapabilitiesAfterRuntimeCloseThrows() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        await runtime.close()
        do {
            _ = try await runtime.capabilities()
            XCTFail("Expected NativeRuntimeError(.invalidInput) — runtime is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
    }

    func testOpenModelAfterRuntimeCloseThrows() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        await runtime.close()
        do {
            _ = try await runtime.openModel(
                config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
            )
            XCTFail("Expected NativeRuntimeError(.invalidInput) — runtime is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
    }

    func testForeignModelTypeRejected() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let fake = FakeNativeModel()
        do {
            _ = try await runtime.openSession(
                config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
                model: fake
            )
            XCTFail("Expected NativeRuntimeError(.invalidInput) — model is not a StubModel")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
            XCTAssertEqual(error.message, "model is not a StubModel")
        }
        await runtime.close()
    }

    func testSessionSendAudioAndTextNoOpSuccess() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()
        try await session.sendAudio(Data(repeating: 0, count: 64), sampleRate: 16000, channels: 1)
        try await session.sendText("hello")
        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testSessionSendAudioAfterCloseThrows() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()
        await session.close()
        do {
            try await session.sendAudio(Data(), sampleRate: 16000, channels: 1)
            XCTFail("Expected NativeRuntimeError(.invalidInput) — session is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
        try await model.close()
        await runtime.close()
    }

    func testSessionSendTextAfterCancelThrows() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()
        try await session.cancel()
        do {
            try await session.sendText("after-cancel")
            XCTFail("Expected NativeRuntimeError(.cancelled)")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .cancelled)
        }
        await session.close()
        try await model.close()
        await runtime.close()
    }

    func testSessionPollEventAfterCloseThrows() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()
        await session.close()
        do {
            _ = try await session.pollEvent(timeout: 0)
            XCTFail("Expected NativeRuntimeError(.invalidInput) — session is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
        try await model.close()
        await runtime.close()
    }

    func testSessionCancelAfterCloseThrows() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()
        await session.close()
        do {
            try await session.cancel()
            XCTFail("Expected NativeRuntimeError(.invalidInput) — session is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
        try await model.close()
        await runtime.close()
    }

    func testSessionCloseIsIdempotent() async throws {
        let (runtime, model, session) = try await Self.openSessionDefault()
        await session.close()
        await session.close() // second close hits the early-return guard
        // Model should still close successfully — release was performed exactly once.
        try await model.close()
        await runtime.close()
    }

    func testPollEventAfterScriptExhaustedSleepsAndReturnsNil() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let anyModel = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        let stubModel = anyModel as! StubModel
        // Bypass the default demo script so the timeout-sleep branch is hit
        // immediately on the first poll. Match openSession()'s borrow() so
        // session.close() balances the borrow/release count.
        await stubModel.borrow()
        let session = StubSession(
            config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
            model: stubModel,
            artifactDigest: "sha256:test",
            script: []
        )

        let start = Date()
        let event = try await session.pollEvent(timeout: 0.05)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertNil(event)
        XCTAssertGreaterThanOrEqual(elapsed, 0.04)

        await session.close()
        try await stubModel.close()
        await runtime.close()
    }

    func testModelWarmAndEvictSucceed() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        try await model.warm()
        try await model.evict()
        try await model.close()
        await runtime.close()
    }

    func testModelWarmAfterCloseThrows() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        try await model.close()
        do {
            try await model.warm()
            XCTFail("Expected NativeRuntimeError(.invalidInput) — model is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
        await runtime.close()
    }

    func testModelEvictAfterCloseThrows() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )
        try await model.close()
        do {
            try await model.evict()
            XCTFail("Expected NativeRuntimeError(.invalidInput) — model is closed")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }
        await runtime.close()
    }

    func testCrossRuntimeModelRejected() async throws {
        let runtime1 = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test1"),
            telemetrySink: nil
        )
        let runtime2 = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test2"),
            telemetrySink: nil
        )
        let modelOnRuntime1 = try await runtime1.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )

        do {
            _ = try await runtime2.openSession(
                config: NativeSessionConfig(modelURI: "model:test", capability: "chat.completion"),
                model: modelOnRuntime1
            )
            XCTFail("Expected NativeRuntimeError(.invalidInput) — model belongs to a different runtime")
        } catch let error as NativeRuntimeError {
            XCTAssertEqual(error.status, .invalidInput)
        }

        try await modelOnRuntime1.close()
        await runtime1.close()
        await runtime2.close()
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
}

// Stand-in conformer used to verify StubRuntime.openSession rejects models
// that did not originate from a StubRuntime. Mirrors the cross-runtime trap
// noted in project_runtime_abi_bindings.md (item 7).
private actor FakeNativeModel: NativeModel {
    func warm() async throws {}
    func evict() async throws {}
    func close() async throws {}
}

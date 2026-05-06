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
}

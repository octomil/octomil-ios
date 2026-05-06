import Foundation
import XCTest
@testable import Octomil

final class StubTelemetrySinkTests: XCTestCase {

    func testModelLoadedFiresFromOpenModel() async throws {
        let receiver = TelemetryReceiver()
        let sink: NativeTelemetrySink = { event in
            receiver.append(event)
        }

        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: sink
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(
                modelURI: "model:test",
                artifactDigest: "sha256:test",
                engineHint: "llama_cpp",
                policyPreset: "default"
            )
        )

        let snapshot = receiver.snapshot
        XCTAssertEqual(snapshot.count, 1, "exactly one telemetry event from openModel")

        guard let first = snapshot.first,
              case .modelLoaded(let payload, let envelope) = first else {
            XCTFail("Expected .modelLoaded, got \(String(describing: snapshot.first))")
            return
        }
        XCTAssertEqual(payload.engine, "llama_cpp")
        XCTAssertEqual(payload.modelID, "model:test")
        XCTAssertEqual(payload.artifactDigest, "sha256:test")
        XCTAssertEqual(payload.policyPreset, "default")
        XCTAssertEqual(envelope.artifactDigest, "sha256:test")

        try await model.close()
        await runtime.close()
    }

    func testTelemetrySinkNilDoesNotCrash() async throws {
        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/test"),
            telemetrySink: nil
        )
        let model = try await runtime.openModel(
            config: NativeModelConfig(modelURI: "model:test", artifactDigest: "sha256:test")
        )

        try await model.close()
        await runtime.close()
    }
}

private final class TelemetryReceiver: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [NativeEvent] = []

    func append(_ event: NativeEvent) {
        lock.withLock { _events.append(event) }
    }

    var snapshot: [NativeEvent] {
        lock.withLock { _events }
    }
}

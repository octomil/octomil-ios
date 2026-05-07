import Foundation
import XCTest
@testable import Octomil

/// End-to-end happy-path smoke for the OCT-104 stub. Covers the
/// narrative the demo app will follow:
///
/// 1. Open `StubRuntime` with a telemetry sink (the audit-log path).
/// 2. Open a model — assert `MODEL_LOADED` reaches the sink.
/// 3. Open a session bound to the model.
/// 4. Drain the scripted timeline via `session.events()`.
/// 5. Assert the terminal event is `sessionCompleted(.ok)` and that the
///    operational envelope (request_id / route_id / trace_id) propagates
///    from session config onto every event — audit logs depend on it.
///
/// The dedicated lifecycle / event / telemetry tests cover individual
/// surfaces; this one checks they compose. The PR test plan calls this
/// "manual smoke from the demo entry point"; the demo entry point lives
/// in `octomil-app-ios` (separate repo), so on-device verification belongs
/// in that repo's PR. What `octomil-ios` can validate is the contract,
/// and that's what this test does.
final class StubDemoFlowSmokeTests: XCTestCase {

    func testFullDemoFlow() async throws {
        let receiver = TelemetryReceiver()
        let sink: NativeTelemetrySink = { event in receiver.append(event) }

        let runtime = try await StubRuntime.open(
            config: NativeRuntimeConfig(artifactRoot: "/tmp/demo"),
            telemetrySink: sink
        )

        let model = try await runtime.openModel(
            config: NativeModelConfig(
                modelURI: "demo:scribe-v1",
                artifactDigest: "sha256:demo",
                engineHint: "llama_cpp",
                policyPreset: "scribe"
            )
        )

        let session = try await runtime.openSession(
            config: NativeSessionConfig(
                modelURI: "demo:scribe-v1",
                capability: "chat.completion",
                requestID: "req-001",
                routeID: "route-on-device",
                traceID: "trace-demo-1"
            ),
            model: model
        )

        var sessionEvents: [NativeEvent] = []
        for try await event in await session.events(pollInterval: 0) {
            sessionEvents.append(event)
        }

        // Default demo timeline is 9 events ending in sessionCompleted(.ok).
        XCTAssertEqual(sessionEvents.count, 9)
        guard case .sessionCompleted(let completion, _) = sessionEvents.last else {
            XCTFail("Expected sessionCompleted as terminal event, got \(String(describing: sessionEvents.last))")
            return
        }
        XCTAssertEqual(completion.terminalStatus, .ok)
        XCTAssertTrue(completion.capabilityVerified)

        // MODEL_LOADED reached the audit-log sink with a populated envelope.
        let telemetry = receiver.snapshot
        XCTAssertEqual(telemetry.count, 1, "exactly one MODEL_LOADED telemetry event from openModel")
        guard let first = telemetry.first,
              case .modelLoaded(let modelLoaded, let modelEnvelope) = first else {
            XCTFail("Expected modelLoaded telemetry event, got \(String(describing: telemetry.first))")
            return
        }
        XCTAssertEqual(modelLoaded.engine, "llama_cpp")
        XCTAssertEqual(modelLoaded.modelID, "demo:scribe-v1")
        XCTAssertEqual(modelLoaded.artifactDigest, "sha256:demo")
        XCTAssertEqual(modelLoaded.policyPreset, "scribe")
        XCTAssertEqual(modelEnvelope.artifactDigest, "sha256:demo")
        XCTAssertEqual(modelEnvelope.engineVersion, "stub-1.0")

        // Session-event envelopes carry the IDs from session config so the
        // audit log can correlate events to their originating call.
        guard case .sessionStarted(_, let sessionEnvelope) = sessionEvents.first else {
            XCTFail("Expected sessionStarted as first event, got \(String(describing: sessionEvents.first))")
            return
        }
        XCTAssertEqual(sessionEnvelope.requestID, "req-001")
        XCTAssertEqual(sessionEnvelope.routeID, "route-on-device")
        XCTAssertEqual(sessionEnvelope.traceID, "trace-demo-1")

        // events() finishes on sessionCompleted, so session is fully drained.
        // Cleanup follows cascade order: session -> model -> runtime.
        await session.close()
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

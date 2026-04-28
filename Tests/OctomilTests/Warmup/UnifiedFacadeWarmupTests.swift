import Foundation
import XCTest

@testable import Octomil

/// Capability-lifecycle parity coverage for the new
/// ``Octomil.warmup(model:capability:)`` dispatcher and the
/// ``audio.speech.warmup`` reuse contract.
///
/// The unified facade requires ``initialize()`` before any of its
/// namespaces become reachable; these tests assert the warmup
/// dispatcher's not-initialized contract independently of the
/// end-to-end path covered by ``AudioSpeechFacadeTests``.
final class UnifiedFacadeWarmupTests: XCTestCase {

    func testWarmupTtsThrowsBeforeInitialize() async {
        let octomil = Octomil(publishableKey: "oct_pub_test_key")
        do {
            _ = try await octomil.warmup(model: "kokoro-82m", capability: .tts)
            XCTFail("expected OctomilNotInitializedError")
        } catch is OctomilNotInitializedError {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testWarmupTranscriptionThrowsBeforeInitialize() async {
        let octomil = Octomil(publishableKey: "oct_pub_test_key")
        do {
            _ = try await octomil.warmup(model: "whisper-base", capability: .transcription)
            XCTFail("expected OctomilNotInitializedError")
        } catch is OctomilNotInitializedError {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAudioFacadeRequiresInitialize() {
        let octomil = Octomil(publishableKey: "oct_pub_test_key")
        XCTAssertThrowsError(try octomil.audio) { error in
            XCTAssertTrue(error is OctomilNotInitializedError)
        }
    }

    func testWarmupCapabilityRawValuesAreStable() {
        XCTAssertEqual(Octomil.WarmupCapability.tts.rawValue, "tts")
        XCTAssertEqual(Octomil.WarmupCapability.transcription.rawValue, "transcription")
    }
}

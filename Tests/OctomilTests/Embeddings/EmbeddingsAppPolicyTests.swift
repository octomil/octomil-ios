import Foundation
import XCTest

@testable import Octomil

/// Capability-lifecycle parity coverage for ``embeddings.create``
/// app + policy routing. The iOS SDK does not yet ship a local
/// embeddings backend, so ``.localOnly``/``.private`` must refuse
/// the call rather than silently routing to cloud.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class EmbeddingsAppPolicyTests: XCTestCase {

    func testEnforcePolicyRejectsLocalOnly() {
        do {
            try FacadeEmbeddings.enforcePolicy(
                model: "nomic-embed-text",
                explicit: .localOnly,
                app: nil
            )
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed(let reason) {
            XCTAssertTrue(reason.contains("local_only"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testEnforcePolicyRejectsPrivate() {
        do {
            try FacadeEmbeddings.enforcePolicy(
                model: "nomic-embed-text",
                explicit: .private,
                app: nil
            )
            XCTFail("expected cloudFallbackDisallowed")
        } catch OctomilError.cloudFallbackDisallowed {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testEnforcePolicyDerivesFromAppManifest() {
        let app = AppManifest(models: [
            AppModelEntry(
                id: "nomic-embed-text",
                capability: .embedding,
                delivery: .bundled,
                bundledPath: "Models/nomic.mlmodelc"
            )
        ])
        do {
            try FacadeEmbeddings.enforcePolicy(
                model: "@app/notes/embedding",
                explicit: nil,
                app: app
            )
            XCTFail("expected cloudFallbackDisallowed via manifest-derived local_only")
        } catch OctomilError.cloudFallbackDisallowed {
            // expected — bundled delivery → effectiveRoutingPolicy = .localOnly
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testEnforcePolicyAllowsCloudFirst() throws {
        // Cloud-first lets the embeddings cloud call go through; the
        // facade's gate must NOT raise.
        XCTAssertNoThrow(try FacadeEmbeddings.enforcePolicy(
            model: "nomic-embed-text",
            explicit: .cloudFirst,
            app: nil
        ))
    }

    func testEnforcePolicyAllowsAuto() throws {
        XCTAssertNoThrow(try FacadeEmbeddings.enforcePolicy(
            model: "nomic-embed-text",
            explicit: .auto,
            app: nil
        ))
    }

    func testEnforcePolicyAllowsNoPolicyAndNoApp() throws {
        // No policy + no app → permissive. Embeddings still routes
        // to cloud, but that is the contract default.
        XCTAssertNoThrow(try FacadeEmbeddings.enforcePolicy(
            model: "nomic-embed-text",
            explicit: nil,
            app: nil
        ))
    }
}

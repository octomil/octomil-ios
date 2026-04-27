import Foundation
import XCTest

@testable import Octomil

/// Reviewer P1 regressions for the iOS prepare lifecycle. Covers
/// the three findings from the PR 193 review:
///
///   1. ``safeJoin`` rejects ancestor-symlink escapes.
///   2. ``source="static_recipe"`` candidates pass validation
///      without planner-supplied digest / downloadUrls.
///   3. Static-recipe prepare materializes the archive into the
///      backend-ready layout (model.onnx / voices.bin / etc.) AND
///      the cache-hit branch idempotently re-runs materialization
///      so a partial extraction completes.
final class PrepareReviewerP1Tests: XCTestCase {
    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-pm-p1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSafeJoinRefusesSymlinkAncestorEscape() throws {
        let destDir = tmpDir.appendingPathComponent("artifact")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let outside = tmpDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        // Plant a symlink inside destDir whose target is outside.
        // Without the symlink-aware safeJoin, the lexical check
        // would accept ``linkdir/escaped.txt`` and a subsequent
        // moveItem would write to ``outside/escaped.txt``.
        try FileManager.default.createSymbolicLink(at: destDir.appendingPathComponent("linkdir"), withDestinationURL: outside)
        XCTAssertThrowsError(try DurableDownloader.safeJoin(destDir: destDir, relativePath: "linkdir/escaped.txt"))
    }

    func testCanPrepareAcceptsStaticRecipeCandidateWithoutDigest() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let candidate = PrepareCandidate(
            locality: "local",
            engine: "sherpa-onnx",
            artifact: PrepareArtifactPlan(
                modelId: "kokoro-82m",
                source: "static_recipe",
                recipeId: "kokoro-82m"
            )
        )
        // Pre-fix: validateForPrepare rejected for missing digest.
        XCTAssertTrue(pm.canPrepare(candidate))
    }

    func testCanPrepareRejectsStaticRecipeWithUnknownRecipeId() throws {
        let pm = try PrepareManager(cacheDir: tmpDir)
        let candidate = PrepareCandidate(
            locality: "local",
            artifact: PrepareArtifactPlan(
                modelId: "x",
                source: "static_recipe",
                recipeId: "nonexistent-private-app"
            )
        )
        XCTAssertFalse(pm.canPrepare(candidate))
    }

    func testStaticRecipePrepareMaterializesBackendReadyLayout() async throws {
        // Build a tarball with the canonical Kokoro layout and
        // register a recipe whose digest matches it, then pre-stage
        // the archive at the cache-hit location so prepare(...)
        // takes the alreadyVerified branch and still runs the
        // recipe's materialization plan.
        //
        // We exercise the cache-hit path rather than the
        // network-download path because URLSession on iOS won't
        // emit an HTTPURLResponse for file:// URLs (which would
        // make a stubbed downloader fail at the response cast).
        // The reviewer P1 fix wires Materializer into BOTH
        // branches, so cache-hit coverage is sufficient to prove
        // the layout is produced — and arguably the more important
        // one (a partially extracted layout from an interrupted
        // run gets repaired here).
        let archive = try makeKokoroLayoutTarball(in: tmpDir)
        let payload = try Data(contentsOf: archive)
        let archiveDigest = "sha256:" + sha256Hex(payload)

        let recipe = StaticRecipe(
            modelId: "kokoro-test",
            file: StaticRecipeFile(
                relativePath: "kokoro-en-v0_19.tar.bz2",
                url: archive.deletingLastPathComponent(),
                digest: archiveDigest
            ),
            materialization: MaterializationPlan(
                kind: .archive,
                source: "kokoro-en-v0_19.tar.bz2",
                archiveFormat: .tarBz2,
                stripPrefix: "kokoro-en-v0_19/",
                requiredOutputs: ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data/phontab"]
            )
        )
        StaticRecipeRegistry.shared.register(recipe, under: "kokoro-test")

        let cacheDir = tmpDir.appendingPathComponent("cache")
        let pm = try PrepareManager(cacheDir: cacheDir)
        // Pre-stage the archive at the cache-hit location.
        let artifactDir = try pm.artifactDirFor("kokoro-test")
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: archive, to: artifactDir.appendingPathComponent("kokoro-en-v0_19.tar.bz2"))

        let candidate = PrepareCandidate(
            locality: "local",
            engine: "sherpa-onnx",
            artifact: PrepareArtifactPlan(
                modelId: "kokoro-test",
                source: "static_recipe",
                recipeId: "kokoro-test"
            )
        )

        let outcome = try await pm.prepare(candidate, mode: .lazy)
        let dir = outcome.artifactDir
        XCTAssertTrue(outcome.cached, "expected cache-hit branch to run")
        // Reviewer P1 (#2): post-cache-hit materialization MUST
        // produce the backend-ready layout — not just leave the
        // tarball on disk.
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.onnx").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("voices.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tokens.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("espeak-ng-data/phontab").path))
    }

    func testMaterializerUnpacksKokoroLayoutDirectly() throws {
        // Direct Materializer test — proves the post-download
        // branch produces the same layout as the cache-hit one.
        // Mirrors the integration test above, minus the network
        // path that URLSession can't simulate cleanly.
        let archive = try makeKokoroLayoutTarball(in: tmpDir)
        let artifactDir = tmpDir.appendingPathComponent("artifact")
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: archive, to: artifactDir.appendingPathComponent("kokoro-en-v0_19.tar.bz2"))

        let plan = MaterializationPlan(
            kind: .archive,
            source: "kokoro-en-v0_19.tar.bz2",
            archiveFormat: .tarBz2,
            stripPrefix: "kokoro-en-v0_19/",
            requiredOutputs: ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data/phontab"]
        )
        try Materializer.materialize(plan: plan, in: artifactDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("model.onnx").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("voices.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("tokens.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("espeak-ng-data/phontab").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent(".octomil-materialized").path))

        // Re-run is idempotent: marker present + outputs present →
        // no-op. Touch a sentinel inside the dir to confirm
        // extraction did NOT clobber it.
        let sentinel = artifactDir.appendingPathComponent("model.onnx")
        let before = try FileManager.default.attributesOfItem(atPath: sentinel.path)[.modificationDate] as? Date
        try Materializer.materialize(plan: plan, in: artifactDir)
        let after = try FileManager.default.attributesOfItem(atPath: sentinel.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after, "second materialize should be a no-op when marker is valid")
    }

    func testMaterializerRecoversFromPartialExtraction() throws {
        // Reviewer P1 (#2) follow-on: a previous run that crashed
        // before writing the marker leaves a partial layout. The
        // next prepare must detect the missing marker and re-run
        // extraction, NOT silently treat the partial tree as done.
        let archive = try makeKokoroLayoutTarball(in: tmpDir)
        let artifactDir = tmpDir.appendingPathComponent("artifact")
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: archive, to: artifactDir.appendingPathComponent("kokoro-en-v0_19.tar.bz2"))

        let plan = MaterializationPlan(
            kind: .archive,
            source: "kokoro-en-v0_19.tar.bz2",
            archiveFormat: .tarBz2,
            stripPrefix: "kokoro-en-v0_19/",
            requiredOutputs: ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data/phontab"]
        )
        // Simulate a partial extraction: only one required output
        // is present, no marker.
        try Data("partial".utf8).write(to: artifactDir.appendingPathComponent("model.onnx"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent(".octomil-materialized").path))

        try Materializer.materialize(plan: plan, in: artifactDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("voices.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("espeak-ng-data/phontab").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent(".octomil-materialized").path))
    }

    // MARK: - helpers

    private func makeKokoroLayoutTarball(in dir: URL) throws -> URL {
        // Build a Kokoro-shape tarball under tmpDir and return its
        // URL. Uses the system ``tar`` tool — same one the
        // Materializer shells out to — so the on-disk shape exactly
        // matches the upstream release archive.
        let src = dir.appendingPathComponent("_src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let layout: [(String, Data)] = [
            ("kokoro-en-v0_19/model.onnx", Data("fake-onnx".utf8)),
            ("kokoro-en-v0_19/voices.bin", Data("fake-voices".utf8)),
            ("kokoro-en-v0_19/tokens.txt", Data("fake-tokens".utf8)),
            ("kokoro-en-v0_19/espeak-ng-data/phontab", Data("fake-phontab".utf8)),
        ]
        for (rel, data) in layout {
            let full = src.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: full.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: full)
        }
        let archive = dir.appendingPathComponent("kokoro-en-v0_19.tar.bz2")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.currentDirectoryURL = src
        proc.arguments = ["-c", "-j", "-f", archive.path, "kokoro-en-v0_19"]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, "tar failed to build fixture archive")
        return archive
    }

    private func sha256Hex(_ data: Data) -> String {
        // CryptoKit is already imported by the prepare module; use
        // it here too so the test stays consistent with what
        // ``digestMatches`` checks.
        var hasher = CryptoKit.SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit

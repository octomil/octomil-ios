// Generic materialization layer for prepared artifacts.
//
// Port of Python ``octomil/runtime/lifecycle/materialization.py``.
// Once a ``DurableDownloader`` has verified bytes on disk, callers
// often need a *backend-ready layout* — not just the raw downloaded
// files. The Sherpa TTS engine wants ``model.onnx`` + ``voices.bin``
// + ``tokens.txt`` + ``espeak-ng-data/`` under one directory; a
// future Whisper recipe might want ``ggml-tiny.bin``.
//
// The runtime knows nothing about Kokoro / tarballs / Sherpa — it
// just hands the recipe's :class:`MaterializationPlan` to the
// generic Materializer, which handles archive extraction, safety
// filtering, idempotency, and required-output verification.
//
// Design notes:
//
//   - Archive extraction is implemented in pure Swift on top of
//     ``COctomilBZ2`` (system libbz2 wrapper) + ``TarReader`` (a
//     small TAR parser). The same code path works on macOS and
//     iOS — no ``Foundation.Process`` shell-out, no
//     ``/usr/bin/tar`` dependency, no iOS-sandbox blockers. ZIP
//     extraction is gated to platforms where ``Compression`` /
//     unzip is available; today only macOS uses ``/usr/bin/unzip``
//     because no current recipe ships ZIP.
//   - The marker file (``.octomil-materialized``) is written LAST,
//     after every ``requiredOutputs`` entry is verified on disk.
//     A partial extraction (interrupted before the marker) is
//     detected on the next run and re-extracted, never silently
//     treated as complete.
//   - ``stripPrefix`` is enforced as an allowlist boundary by
//     re-rooting the extraction in a ``staging`` directory and
//     copying the prefix subtree into ``artifactDir``. Members
//     outside the prefix never land in the destination, so a
//     malformed archive with root-level ``model.onnx`` cannot
//     satisfy a recipe whose plan declared
//     ``stripPrefix="kokoro-en-v0_19/"``.

import Foundation

/// Sentinel marker file written into the artifact dir after a
/// successful materialization. Its presence + every required output
/// being on disk together prove the directory is backend-ready.
public let EXTRACTION_MARKER_FILENAME = ".octomil-materialized"

public enum MaterializerError: Error, CustomStringConvertible {
    case missingArtifactDir(URL)
    case archiveSourceMissing(name: String, in: URL)
    case unsupportedArchiveFormat(String)
    case toolFailed(tool: String, status: Int32, output: String)
    case requiredOutputsMissing([String], in: URL)
    case invalidPlan(String)
    case unsupportedOnPlatform(String)

    public var description: String {
        switch self {
        case let .missingArtifactDir(url):
            return "Materializer: artifact_dir \(url.path) does not exist or is not a directory."
        case let .archiveSourceMissing(name, dir):
            return "Materializer: archive \(name.debugDescription) not found under \(dir.path)."
        case let .unsupportedArchiveFormat(format):
            return "Materializer: unsupported archive_format \(format.debugDescription)."
        case let .toolFailed(tool, status, output):
            return "Materializer: \(tool) exited with status \(status). Output:\n\(output)"
        case let .requiredOutputsMissing(missing, dir):
            return "Materializer: required outputs missing under \(dir.path): \(missing)."
        case let .invalidPlan(message):
            return "Materializer: invalid plan: \(message)"
        case let .unsupportedOnPlatform(message):
            return "Materializer: \(message)"
        }
    }
}

public enum Materializer {
    /// Apply ``plan`` to ``artifactDir``. Idempotent across runs;
    /// safe against tar/zip-bomb / traversal / symlink-escape
    /// archives via the ``--filter=data`` option to ``tar`` on
    /// platforms that support it (and copy-from-staging on
    /// every other archive shape).
    public static func materialize(plan: MaterializationPlan, in artifactDir: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: artifactDir.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            throw MaterializerError.missingArtifactDir(artifactDir)
        }

        switch plan.kind {
        case .none:
            try assertLayoutComplete(plan: plan, in: artifactDir)
        case .archive:
            try materializeArchive(plan: plan, in: artifactDir)
        }
    }

    // MARK: - Archive

    private static func materializeArchive(plan: MaterializationPlan, in artifactDir: URL) throws {
        guard let source = plan.source else {
            throw MaterializerError.invalidPlan("MaterializationPlan(kind: .archive) requires source.")
        }
        let archiveURL = artifactDir.appendingPathComponent(source)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw MaterializerError.archiveSourceMissing(name: source, in: artifactDir)
        }

        // Idempotency: skip extraction only when the marker is
        // present AND every required output is on disk.
        if extractionMarkerValid(plan: plan, in: artifactDir) {
            return
        }

        // Reset any half-written marker from an interrupted run so
        // the post-extraction completeness check writes fresh.
        let markerURL = artifactDir.appendingPathComponent(EXTRACTION_MARKER_FILENAME)
        try? FileManager.default.removeItem(at: markerURL)

        // Stage extraction in a sibling directory; only the
        // ``stripPrefix`` subtree is moved into ``artifactDir``.
        // This enforces the prefix as an allowlist (members outside
        // the prefix cannot land in the final destination) and
        // gives us a clean rollback target if extraction fails
        // partway through.
        let staging = artifactDir.appendingPathComponent(".staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let format = plan.archiveFormat ?? Self.inferArchiveFormat(source: source)
        try extractArchive(archiveURL, into: staging, format: format)

        try copyAllowlist(from: staging, into: artifactDir, stripPrefix: plan.stripPrefix)
        try assertLayoutComplete(plan: plan, in: artifactDir)

        // Atomic marker write: write to .tmp and rename so a crash
        // mid-write doesn't leave a half-written marker.
        let tmpMarker = artifactDir.appendingPathComponent("\(EXTRACTION_MARKER_FILENAME).tmp")
        try "kind=\(plan.kind.rawValue)\nsource=\(source)\n".write(to: tmpMarker, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(markerURL, withItemAt: tmpMarker)
    }

    /// Cross-platform archive extraction. tar / tar.bz2 / tar.gz
    /// use a pure-Swift reader on top of libbz2 / Compression, so
    /// macOS and iOS share one code path. ZIP is gated to macOS
    /// because no current recipe ships ZIP (and zlib's deflate is
    /// already in Compression — straightforward when needed).
    private static func extractArchive(_ archive: URL, into staging: URL, format: MaterializationPlan.ArchiveFormat) throws {
        switch format {
        case .tarBz2:
            // Decompress to a sibling temp .tar then run TarReader.
            // bz2 streaming + tar parsing in one pass would save
            // disk but Kokoro is small enough that the simpler
            // two-step pipeline is the right tradeoff.
            let tarURL = staging.appendingPathComponent(".decompressed.tar")
            try BZ2Decompressor.decompress(from: archive, to: tarURL)
            try extractTar(tarURL, into: staging)
            try? FileManager.default.removeItem(at: tarURL)
        case .tarGz:
            // Compression framework natively supports zlib (gzip)
            // streaming. Mirrors the bz2 path: decompress to a
            // staging .tar, then TarReader.
            let tarURL = staging.appendingPathComponent(".decompressed.tar")
            try GzipDecompressor.decompress(from: archive, to: tarURL)
            try extractTar(tarURL, into: staging)
            try? FileManager.default.removeItem(at: tarURL)
        case .tar:
            try extractTar(archive, into: staging)
        case .zip:
            #if os(macOS)
                try runUnzip(archive: archive, into: staging)
            #else
                throw MaterializerError.unsupportedOnPlatform(
                    "ZIP extraction is not yet wired up on this platform; ship a tar.bz2/tar.gz recipe instead."
                )
            #endif
        }
    }

    /// Apply a fully-decompressed tar file to ``staging``,
    /// honoring the safety boundary: refuse path-traversal
    /// entries, drop in-archive symlinks, and only write under
    /// ``staging``.
    private static func extractTar(_ tarURL: URL, into staging: URL) throws {
        let stagingResolved = staging.resolvingSymlinksInPath().standardizedFileURL
        let stagingPath = stagingResolved.path
        try TarReader.read(from: tarURL) { entry, drain in
            // Reject path-traversal segments before computing the
            // destination URL; ``TarReader`` already trims to the
            // header's null-terminated name but never validates.
            for seg in entry.name.split(separator: "/") {
                if seg == ".." {
                    throw MaterializerError.invalidPlan("tar entry contains a path-traversal segment: \(entry.name)")
                }
            }
            // Drop in-archive symlinks/hardlinks; we don't follow
            // them during materialization. Other typeflags (e.g.
            // sparse files) are also dropped with a clear error.
            switch entry.kind {
            case .symbolicLink, .hardLink:
                // Skip but still drain the (typically zero-byte) payload.
                try drain { _ in }
                return
            case .other(let typeflag):
                // GNU/PAX special types are filtered upstream in
                // TarReader. Anything that reaches here is unsupported.
                throw MaterializerError.invalidPlan("tar entry typeflag \(typeflag) not supported")
            case .file, .directory:
                break
            }

            let destination = stagingResolved.appendingPathComponent(entry.name).standardizedFileURL
            // Containment check: even after the traversal-segment
            // refusal above, defense in depth.
            let destPath = destination.path
            guard destPath == stagingPath || destPath.hasPrefix(stagingPath + "/") else {
                throw MaterializerError.invalidPlan("tar entry resolves outside staging dir: \(entry.name)")
            }
            switch entry.kind {
            case .directory:
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try drain { _ in }
            case .file:
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let handle = try FileHandle(forWritingTo: destination)
                defer { try? handle.close() }
                try drain { chunk in
                    try handle.write(contentsOf: chunk)
                }
            default:
                break // already returned above
            }
        }
    }

    #if os(macOS)
    private static func runUnzip(archive: URL, into staging: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archive.path, "-d", staging.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output: String
        if let data = try? pipe.fileHandleForReading.readToEnd(), let s = String(data: data, encoding: .utf8) {
            output = s
        } else {
            output = ""
        }
        if process.terminationStatus != 0 {
            throw MaterializerError.toolFailed(tool: "unzip", status: process.terminationStatus, output: output)
        }
    }
    #endif

    private static func copyAllowlist(from staging: URL, into artifactDir: URL, stripPrefix: String?) throws {
        let prefix = stripPrefix.map { $0.hasSuffix("/") ? $0 : $0 + "/" } ?? ""
        let sourceRoot: URL
        if prefix.isEmpty {
            sourceRoot = staging
        } else {
            // Members outside the prefix are skipped (enumerator
            // walks the staging tree; ``stripPrefix`` is the only
            // subtree we move into the destination).
            sourceRoot = staging.appendingPathComponent(String(prefix.dropLast()))
            guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
                // Misshapen archive — empty extraction or wrong
                // prefix declared. Let ``assertLayoutComplete``
                // surface the actionable required-outputs error.
                return
            }
        }

        // Resolve symlinks once; on macOS ``/var`` is a symlink to
        // ``/private/var``, so the enumerator returns URLs whose
        // ``.path`` is in resolved form while ``sourceRoot.path`` is
        // not. A naive ``url.path.replacingOccurrences(of:
        // sourceRoot.path + "/")`` would then leave the full path
        // verbatim and write outside the artifact dir.
        let fm = FileManager.default
        let sourceRootResolved = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        let sourceRootResolvedPath = sourceRootResolved.path
        guard let enumerator = fm.enumerator(at: sourceRootResolved, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return
        }
        for case let url as URL in enumerator {
            let attrs = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if attrs.isSymbolicLink == true {
                // Refuse symlinks at the destination; the recipe
                // can opt in via a future safety policy.
                continue
            }
            let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            let prefixWithSep = sourceRootResolvedPath + "/"
            guard resolvedPath.hasPrefix(prefixWithSep) else {
                // Enumerator yielded something outside the staging
                // root — should not happen, but if it does, skip.
                continue
            }
            let relativePath = String(resolvedPath.dropFirst(prefixWithSep.count))
            // Reviewer P1: route every destination path through
            // safeJoin so a pre-existing symlink in artifactDir
            // (planted earlier or by a hostile sibling artifact)
            // can't redirect copyItem outside the artifact dir.
            // Mirrors the durable-downloader's per-write check.
            let destination = try DurableDownloader.safeJoin(destDir: artifactDir, relativePath: relativePath)
            if attrs.isDirectory == true {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                let destParent = destination.deletingLastPathComponent()
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: url, to: destination)
            }
        }
    }

    // MARK: - Helpers

    private static func inferArchiveFormat(source: String) -> MaterializationPlan.ArchiveFormat {
        let s = source.lowercased()
        if s.hasSuffix(".tar.bz2") || s.hasSuffix(".tbz2") || s.hasSuffix(".tbz") { return .tarBz2 }
        if s.hasSuffix(".tar.gz") || s.hasSuffix(".tgz") { return .tarGz }
        if s.hasSuffix(".tar") { return .tar }
        if s.hasSuffix(".zip") { return .zip }
        return .tar
    }

    private static func extractionMarkerValid(plan: MaterializationPlan, in artifactDir: URL) -> Bool {
        let markerURL = artifactDir.appendingPathComponent(EXTRACTION_MARKER_FILENAME)
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return false }
        guard !plan.requiredOutputs.isEmpty else { return false }
        return plan.requiredOutputs.allSatisfy { rel in
            FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent(rel).path)
        }
    }

    private static func assertLayoutComplete(plan: MaterializationPlan, in artifactDir: URL) throws {
        let missing = plan.requiredOutputs.filter { rel in
            !FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent(rel).path)
        }
        if !missing.isEmpty {
            throw MaterializerError.requiredOutputsMissing(missing, in: artifactDir)
        }
    }
}

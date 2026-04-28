// Durable, resumable, multi-URL artifact downloader.
//
// Port of Python ``durable_download.py`` and Node ``durable-download.ts``.
// Streams bytes to ``<destDir>/.parts/<rel>.part`` with HTTP-Range
// resume across attempts, verifies SHA-256 against the artifact's
// digest, and atomically renames into place. Multi-URL fallback list
// of endpoints; expired endpoints skipped before any HTTP request.
//
// Crash-resume via a JSON sidecar at ``<cacheDir>/.progress.json``
// (Python uses sqlite, Node + Swift use JSON to keep the contract
// portable without native deps). The journal is *advisory*: at open
// time we cross-check the row against the on-disk ``.part`` file and
// clamp ``bytesWritten`` to the smaller of the two values.

import CryptoKit
import Foundation

// MARK: - Public types

public struct DownloadEndpoint: Sendable, Codable {
    public let url: URL
    /// ISO-8601 timestamp; endpoints whose ``expiresAt`` is in the
    /// past at fetch time are skipped before any HTTP request.
    public let expiresAt: Date?
    public let headers: [String: String]

    public init(url: URL, expiresAt: Date? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.expiresAt = expiresAt
        self.headers = headers
    }
}

public struct RequiredFile: Sendable, Codable {
    /// Path within the artifact root. ``""`` means the artifact is
    /// single-file and the endpoint URL points directly at it.
    public let relativePath: String
    /// ``sha256:<hex>`` or bare hex; verified after the last byte
    /// is written.
    public let digest: String
    public let sizeBytes: Int64?

    public init(relativePath: String, digest: String, sizeBytes: Int64? = nil) {
        self.relativePath = relativePath
        self.digest = digest
        self.sizeBytes = sizeBytes
    }
}

public struct ArtifactDescriptor: Sendable {
    public let artifactId: String
    public let requiredFiles: [RequiredFile]
    public let endpoints: [DownloadEndpoint]

    public init(artifactId: String, requiredFiles: [RequiredFile], endpoints: [DownloadEndpoint]) {
        self.artifactId = artifactId
        self.requiredFiles = requiredFiles
        self.endpoints = endpoints
    }
}

public struct DownloadResult: Sendable {
    public let artifactId: String
    /// Resolved on-disk paths keyed by relative path.
    public let files: [String: URL]
}

public enum DownloadError: Error, CustomStringConvertible {
    case noEndpoints(artifactId: String)
    case noRequiredFiles(artifactId: String)
    case invalidRelativePath(String, reason: String)
    case checksumMismatch(artifactId: String, relativePath: String, endpointIndex: Int)
    case exhausted(artifactId: String, relativePath: String, lastError: Error?)
    case unexpectedStatus(Int, url: URL)

    public var description: String {
        switch self {
        case let .noEndpoints(artifactId):
            return "Artifact '\(artifactId)' has no download endpoints."
        case let .noRequiredFiles(artifactId):
            return "Artifact '\(artifactId)' has no required_files."
        case let .invalidRelativePath(path, reason):
            return "Required file path '\(path)' is invalid: \(reason)"
        case let .checksumMismatch(artifactId, relativePath, endpointIndex):
            return "Digest mismatch for '\(artifactId)' file '\(relativePath)' from endpoint \(endpointIndex)."
        case let .exhausted(artifactId, relativePath, lastError):
            return "Exhausted all endpoints for '\(artifactId)' file '\(relativePath)'. Last error: \(lastError.map(String.init(describing:)) ?? "unknown")"
        case let .unexpectedStatus(status, url):
            return "Unexpected HTTP \(status) for \(url.absoluteString)"
        }
    }
}

// MARK: - DurableDownloader

public actor DurableDownloader {
    private let cacheDir: URL
    private let urlSession: URLSession
    private let timeoutSeconds: TimeInterval
    private let journal: ProgressJournal
    private let now: @Sendable () -> Date

    public init(
        cacheDir: URL,
        urlSession: URLSession = .shared,
        timeoutSeconds: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.cacheDir = cacheDir
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
        self.now = now
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.journal = try ProgressJournal(path: cacheDir.appendingPathComponent(".progress.json"))
    }

    /// Download every file in the descriptor; return resolved paths.
    /// Throws on exhausted endpoints, checksum mismatch, or empty
    /// metadata.
    public func download(descriptor: ArtifactDescriptor, destDir: URL) async throws -> DownloadResult {
        guard !descriptor.endpoints.isEmpty else {
            throw DownloadError.noEndpoints(artifactId: descriptor.artifactId)
        }
        guard !descriptor.requiredFiles.isEmpty else {
            throw DownloadError.noRequiredFiles(artifactId: descriptor.artifactId)
        }
        // Trust boundary: validate every planner-supplied path before
        // any filesystem or URL operation.
        for required in descriptor.requiredFiles {
            _ = try Self.validateRelativePath(required.relativePath)
        }

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let partsDir = destDir.appendingPathComponent(".parts")
        try FileManager.default.createDirectory(at: partsDir, withIntermediateDirectories: true)

        let lock = try FileLock(
            name: descriptor.artifactId,
            lockDir: cacheDir.appendingPathComponent(".locks")
        )
        try await lock.acquire()
        defer { Task { await lock.release() } }

        var files: [String: URL] = [:]
        for required in descriptor.requiredFiles {
            files[required.relativePath] = try await downloadOne(
                descriptor: descriptor,
                required: required,
                destDir: destDir,
                partsDir: partsDir
            )
        }
        return DownloadResult(artifactId: descriptor.artifactId, files: files)
    }

    // MARK: - One file

    private func downloadOne(
        descriptor: ArtifactDescriptor,
        required: RequiredFile,
        destDir: URL,
        partsDir: URL
    ) async throws -> URL {
        let safeRel = try Self.validateRelativePath(required.relativePath)
        let finalURL = safeRel.isEmpty
            ? destDir.appendingPathComponent("artifact")
            : try Self.safeJoin(destDir: destDir, relativePath: safeRel)
        try FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Cache hit: bytes already on disk + verified.
        if FileManager.default.fileExists(atPath: finalURL.path) {
            if try await Self.digestMatches(filePath: finalURL, expected: required.digest) {
                return finalURL
            }
        }

        let partName = (safeRel.isEmpty ? "artifact" : safeRel.replacingOccurrences(of: "/", with: "_")) + ".part"
        let partURL = partsDir.appendingPathComponent(partName)

        let entry = await journal.get(artifactId: descriptor.artifactId, relativePath: required.relativePath)
        let onDisk = (try? FileManager.default.attributesOfItem(atPath: partURL.path)[.size] as? Int64) ?? 0
        var offset = min(entry.bytesWritten, onDisk)
        if offset != onDisk, FileManager.default.fileExists(atPath: partURL.path) {
            let handle = try FileHandle(forUpdating: partURL)
            try handle.truncate(atOffset: UInt64(offset))
            try handle.close()
        }

        var lastError: Error?
        let ordered = orderEndpoints(count: descriptor.endpoints.count, preferred: entry.endpointIndex)
        for index in ordered {
            let endpoint = descriptor.endpoints[index]
            if isExpired(endpoint, nowDate: now()) { continue }
            do {
                try await fetchOne(
                    endpoint: endpoint,
                    required: required,
                    partURL: partURL,
                    offset: offset,
                    artifactId: descriptor.artifactId,
                    endpointIndex: index
                )
                if try await Self.digestMatches(filePath: partURL, expected: required.digest) {
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try? FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: partURL, to: finalURL)
                    await journal.clear(artifactId: descriptor.artifactId, relativePath: required.relativePath)
                    return finalURL
                }
                // Digest mismatch — drop progress, continue to next endpoint.
                try? FileManager.default.removeItem(at: partURL)
                await journal.clear(artifactId: descriptor.artifactId, relativePath: required.relativePath)
                offset = 0
                lastError = DownloadError.checksumMismatch(
                    artifactId: descriptor.artifactId,
                    relativePath: required.relativePath,
                    endpointIndex: index
                )
            } catch {
                lastError = error
                if let de = error as? DownloadError, case let .unexpectedStatus(status, _) = de,
                   [401, 403, 404, 410].contains(status)
                {
                    // Dead URL: drop progress so the next endpoint
                    // doesn't carry bytes a different host won't
                    // know how to resume.
                    try? FileManager.default.removeItem(at: partURL)
                    await journal.clear(artifactId: descriptor.artifactId, relativePath: required.relativePath)
                    offset = 0
                } else {
                    offset = (try? FileManager.default.attributesOfItem(atPath: partURL.path)[.size] as? Int64) ?? 0
                }
            }
        }

        throw DownloadError.exhausted(
            artifactId: descriptor.artifactId,
            relativePath: required.relativePath,
            lastError: lastError
        )
    }

    private func fetchOne(
        endpoint: DownloadEndpoint,
        required: RequiredFile,
        partURL: URL,
        offset: Int64,
        artifactId: String,
        endpointIndex: Int
    ) async throws {
        let safeRel = try Self.validateRelativePath(required.relativePath)
        let url = Self.resolveURL(base: endpoint.url, relativePath: safeRel)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        for (k, v) in endpoint.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let (bytesStream, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.unexpectedStatus(0, url: url)
        }
        let status = httpResponse.statusCode

        if status == 416, offset > 0 {
            // Stale resume offset; drop and retry from byte zero.
            try? FileManager.default.removeItem(at: partURL)
            await journal.clear(artifactId: artifactId, relativePath: required.relativePath)
            var fresh = request
            fresh.setValue(nil, forHTTPHeaderField: "Range")
            let (retryStream, retryResponse) = try await urlSession.bytes(for: fresh)
            guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                throw DownloadError.unexpectedStatus(
                    (retryResponse as? HTTPURLResponse)?.statusCode ?? 0,
                    url: url
                )
            }
            try await streamToPart(retryStream, partURL: partURL, offset: 0, artifactId: artifactId, relativePath: required.relativePath, endpointIndex: endpointIndex)
            return
        }
        guard status == 200 || status == 206 else {
            throw DownloadError.unexpectedStatus(status, url: url)
        }
        let resume = (status == 206) && offset > 0
        try await streamToPart(bytesStream, partURL: partURL, offset: resume ? offset : 0, artifactId: artifactId, relativePath: required.relativePath, endpointIndex: endpointIndex)
    }

    private func streamToPart(
        _ bytes: URLSession.AsyncBytes,
        partURL: URL,
        offset: Int64,
        artifactId: String,
        relativePath: String,
        endpointIndex: Int
    ) async throws {
        if offset == 0 {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partURL)
        try handle.seek(toOffset: UInt64(offset))
        var bytesWritten = offset
        var lastFlush = bytesWritten
        let chunkSize: Int64 = 64 * 1024
        let flushBytes: Int64 = 4 * 1024 * 1024
        var buffer = Data()
        buffer.reserveCapacity(Int(chunkSize))
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    try handle.write(contentsOf: buffer)
                    bytesWritten += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if bytesWritten - lastFlush >= flushBytes {
                        try handle.synchronize()
                        await journal.record(artifactId: artifactId, relativePath: relativePath, bytesWritten: bytesWritten, endpointIndex: endpointIndex)
                        lastFlush = bytesWritten
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                bytesWritten += Int64(buffer.count)
            }
            try handle.synchronize()
        } catch {
            try? handle.close()
            throw error
        }
        try handle.close()
        await journal.record(artifactId: artifactId, relativePath: relativePath, bytesWritten: bytesWritten, endpointIndex: endpointIndex)
    }

    // MARK: - Static helpers (also exported for unit testing)

    public static func validateRelativePath(_ relativePath: String) throws -> String {
        if relativePath.isEmpty { return "" }
        if relativePath.contains("\u{0000}") {
            throw DownloadError.invalidRelativePath(relativePath, reason: "contains a NUL byte")
        }
        if relativePath.contains("\\") {
            throw DownloadError.invalidRelativePath(relativePath, reason: "uses backslashes; artifacts must be addressed with forward-slash POSIX paths")
        }
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for s in segments {
            if s.isEmpty || s == "." || s == ".." {
                throw DownloadError.invalidRelativePath(relativePath, reason: "must not contain '.', '..', or empty segments")
            }
        }
        if relativePath.hasPrefix("/") {
            throw DownloadError.invalidRelativePath(relativePath, reason: "must be relative")
        }
        // Block Windows drive letters.
        if relativePath.count >= 2,
           let first = relativePath.first,
           first.isASCII, first.isLetter,
           relativePath[relativePath.index(after: relativePath.startIndex)] == ":"
        {
            throw DownloadError.invalidRelativePath(relativePath, reason: "looks like a Windows drive")
        }
        return relativePath
    }

    /// Reviewer P1: lexical containment alone is insufficient. If
    /// ``destDir`` already contains ``linkdir → /tmp/outside``
    /// (planted by an earlier extraction, hostile sibling
    /// artifact, or misconfigured cache), a member like
    /// ``linkdir/escaped.txt`` passes the lexical check but
    /// ``moveItem`` follows the symlink and writes outside the
    /// artifact directory. This function:
    ///
    /// 1. Resolves ``destDir`` through any pre-existing symlinks
    ///    (``URL.resolvingSymlinksInPath()``).
    /// 2. Resolves the deepest existing ancestor of the candidate
    ///    path, then verifies the resolved path is contained.
    /// 3. Walks every existing ancestor under ``destDir`` and
    ///    refuses if any of them is itself a symlink whose target
    ///    leaves ``destDir`` (defense in depth: even if step 2
    ///    happens to land inside, a subsequent ``moveItem``
    ///    follows the link).
    ///
    /// Mirrors Python's ``_safe_join_under`` and Node's
    /// ``safeJoin`` post-PR-12-fix.
    public static func safeJoin(destDir: URL, relativePath: String) throws -> URL {
        let safe = try validateRelativePath(relativePath)
        let baseResolved = realpathExisting(destDir.standardizedFileURL)
        if safe.isEmpty { return baseResolved }
        let candidate = baseResolved.appendingPathComponent(safe).standardizedFileURL
        let candidateResolved = realpathExisting(candidate)
        let basePathWithSep = baseResolved.path + "/"
        guard candidateResolved.path == baseResolved.path || candidateResolved.path.hasPrefix(basePathWithSep) else {
            throw DownloadError.invalidRelativePath(relativePath, reason: "resolves outside the artifact directory")
        }
        // Defense in depth: walk every existing ancestor below
        // ``baseResolved``; refuse if any is a symlink whose target
        // escapes the base. Without this, an in-tree symlink whose
        // target ALSO lives in tree but redirects file writes to a
        // sensitive existing path could slip through step 1.
        var cursor = candidate.deletingLastPathComponent()
        while cursor.path != baseResolved.path && cursor.path != cursor.deletingLastPathComponent().path {
            if let stat = try? FileManager.default.attributesOfItem(atPath: cursor.path),
               let type = stat[.type] as? FileAttributeType, type == .typeSymbolicLink {
                let target = realpathExisting(cursor)
                guard target.path == baseResolved.path || target.path.hasPrefix(basePathWithSep) else {
                    throw DownloadError.invalidRelativePath(relativePath, reason: "crosses a symlink that escapes the artifact directory")
                }
            }
            cursor = cursor.deletingLastPathComponent()
        }
        return candidateResolved
    }

    /// Resolve symlinks for whatever portion of ``url`` exists,
    /// then re-append the not-yet-existing tail. Equivalent to the
    /// Node ``realpathExisting`` helper.
    private static func realpathExisting(_ url: URL) -> URL {
        var head = url.standardizedFileURL
        var tail: [String] = []
        while true {
            if FileManager.default.fileExists(atPath: head.path) {
                let resolved = head.resolvingSymlinksInPath()
                var out = resolved
                for part in tail { out = out.appendingPathComponent(part) }
                return out.standardizedFileURL
            }
            let parent = head.deletingLastPathComponent()
            if parent.path == head.path {
                return url.standardizedFileURL
            }
            tail.insert(head.lastPathComponent, at: 0)
            head = parent
        }
    }

    public static func digestMatches(filePath: URL, expected: String) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return false }
        let expectedHex = (expected.hasPrefix("sha256:") ? String(expected.dropFirst(7)) : expected).lowercased()
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: filePath)
        defer { try? handle.close() }
        let chunk = 64 * 1024
        while true {
            let data = handle.readData(ofLength: chunk)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let actualHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return actualHex == expectedHex
    }

    private static func resolveURL(base: URL, relativePath: String) -> URL {
        if relativePath.isEmpty { return base }
        // Match Python/Node ``f"{base.rstrip('/')}/{rel.lstrip('/')}"``
        // semantics rather than ``URL(string:relativeTo:)``, which
        // strips trailing path components when ``base`` lacks a
        // trailing slash.
        let baseString = base.absoluteString
        let trimmed = baseString.hasSuffix("/") ? String(baseString.dropLast()) : baseString
        let rel = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        return URL(string: "\(trimmed)/\(rel)")!
    }

    nonisolated private func orderEndpoints(count: Int, preferred: Int) -> [Int] {
        let all = Array(0 ..< count)
        guard preferred >= 0, preferred < count else { return all }
        return [preferred] + all.filter { $0 != preferred }
    }

    nonisolated private func isExpired(_ endpoint: DownloadEndpoint, nowDate: Date) -> Bool {
        guard let exp = endpoint.expiresAt else { return false }
        return nowDate >= exp
    }
}

// MARK: - Progress journal

private struct ProgressEntry: Codable, Sendable {
    var bytesWritten: Int64
    var endpointIndex: Int
    var updatedAtUnix: Double
}

private struct ProgressFile: Codable, Sendable {
    var entries: [String: [String: ProgressEntry]]
}

private actor ProgressJournal {
    private let path: URL
    private var state: ProgressFile

    init(path: URL) throws {
        self.path = path
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: path),
           let decoded = try? JSONDecoder().decode(ProgressFile.self, from: data)
        {
            self.state = decoded
        } else {
            self.state = ProgressFile(entries: [:])
        }
    }

    func get(artifactId: String, relativePath: String) -> ProgressEntry {
        state.entries[artifactId]?[relativePath]
            ?? ProgressEntry(bytesWritten: 0, endpointIndex: 0, updatedAtUnix: 0)
    }

    func record(artifactId: String, relativePath: String, bytesWritten: Int64, endpointIndex: Int) {
        var slot = state.entries[artifactId] ?? [:]
        slot[relativePath] = ProgressEntry(
            bytesWritten: bytesWritten,
            endpointIndex: endpointIndex,
            updatedAtUnix: Date().timeIntervalSince1970
        )
        state.entries[artifactId] = slot
        flush()
    }

    func clear(artifactId: String, relativePath: String) {
        guard var slot = state.entries[artifactId] else { return }
        slot.removeValue(forKey: relativePath)
        if slot.isEmpty {
            state.entries.removeValue(forKey: artifactId)
        } else {
            state.entries[artifactId] = slot
        }
        flush()
    }

    private func flush() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let tmp = path.appendingPathExtension("tmp")
        try? data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(path, withItemAt: tmp)
    }
}

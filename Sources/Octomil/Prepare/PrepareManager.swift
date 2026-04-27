// Bridge from a planner candidate to on-disk artifact readiness.
//
// Port of Python ``PrepareManager`` and Node ``prepare-manager.ts``.
// Single owner of artifact materialization for ``sdk_runtime``
// candidates. Wraps :class:`DurableDownloader` (the actual byte pump)
// and threads policy + cache + safe filesystem keys through one
// consistent surface.

import Foundation

public enum PrepareMode: String, Sendable {
    /// Runtime-driven prepare (just-in-time during inference dispatch).
    case lazy
    /// Caller-driven prepare (CLI, ``client.prepare(...)``). Permitted
    /// even when the candidate's ``preparePolicy == .explicitOnly``.
    case explicit
}

/// What ``RuntimeCandidatePlan.preparePolicy`` carries today.
public enum PreparePolicy: String, Sendable, Codable {
    case lazy
    case explicitOnly = "explicit_only"
    case disabled
}

public struct ArtifactDownloadEndpoint: Sendable {
    public let url: URL
    public let expiresAt: Date?
    public let headers: [String: String]

    public init(url: URL, expiresAt: Date? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.expiresAt = expiresAt
        self.headers = headers
    }
}

/// The fields ``PrepareManager`` reads off the planner artifact plan.
/// Concrete planner schemas (today's ``RuntimeArtifactPlan`` Codable
/// type, decoded from the API response) project into this shape.
public struct PrepareArtifactPlan: Sendable {
    public let modelId: String
    public let artifactId: String?
    public let digest: String?
    public let sizeBytes: Int64?
    public let requiredFiles: [String]
    public let downloadUrls: [ArtifactDownloadEndpoint]
    public let manifestUri: URL?
    /// PR C-followup option 2: ``"static_recipe"`` lets the planner
    /// name a built-in recipe instead of redeclaring URL/digest in
    /// every plan. ``nil`` means "use the artifact metadata as-is".
    public let source: String?
    public let recipeId: String?

    public init(
        modelId: String,
        artifactId: String? = nil,
        digest: String? = nil,
        sizeBytes: Int64? = nil,
        requiredFiles: [String] = [],
        downloadUrls: [ArtifactDownloadEndpoint] = [],
        manifestUri: URL? = nil,
        source: String? = nil,
        recipeId: String? = nil
    ) {
        self.modelId = modelId
        self.artifactId = artifactId
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.requiredFiles = requiredFiles
        self.downloadUrls = downloadUrls
        self.manifestUri = manifestUri
        self.source = source
        self.recipeId = recipeId
    }
}

public struct PrepareCandidate: Sendable {
    public let locality: String
    public let engine: String?
    public let artifact: PrepareArtifactPlan?
    public let deliveryMode: String
    public let prepareRequired: Bool
    public let preparePolicy: PreparePolicy

    public init(
        locality: String,
        engine: String? = nil,
        artifact: PrepareArtifactPlan? = nil,
        deliveryMode: String = "sdk_runtime",
        prepareRequired: Bool = true,
        preparePolicy: PreparePolicy = .lazy
    ) {
        self.locality = locality
        self.engine = engine
        self.artifact = artifact
        self.deliveryMode = deliveryMode
        self.prepareRequired = prepareRequired
        self.preparePolicy = preparePolicy
    }
}

public struct PrepareOutcome: Sendable {
    public let artifactId: String
    public let artifactDir: URL
    public let files: [String: URL]
    public let engine: String?
    public let deliveryMode: String
    public let preparePolicy: PreparePolicy
    public let cached: Bool
}

public enum PrepareError: Error, CustomStringConvertible {
    case invalidInput(String)
    case checksumMismatch(String)
    case downloadFailed(String, underlying: Error?)
    case unknownRecipe(String)

    public var description: String {
        switch self {
        case let .invalidInput(message): return message
        case let .checksumMismatch(message): return message
        case let .downloadFailed(message, _): return message
        case let .unknownRecipe(message): return message
        }
    }
}

// MARK: - PrepareManager

public actor PrepareManager {
    public let cacheDir: URL
    private let downloader: DurableDownloader

    public init(cacheDir: URL? = nil, downloader: DurableDownloader? = nil) throws {
        let dir = cacheDir ?? Self.defaultCacheDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDir = dir
        self.downloader = try downloader ?? DurableDownloader(cacheDir: dir)
    }

    /// Pure inspection — does NOT touch disk or network. Returns
    /// ``true`` only when ``prepare(_:mode:)`` is structurally
    /// guaranteed to succeed. Synthetic / malformed candidates
    /// return ``false`` so the routing layer can treat them as
    /// unavailable rather than committing to local and failing.
    public nonisolated func canPrepare(_ candidate: PrepareCandidate) -> Bool {
        do {
            try Self.validateForPrepare(candidate)
            return true
        } catch {
            return false
        }
    }

    /// Compute the deterministic ``<cacheDir>/<safeKey>`` directory
    /// for an artifact id. Mirrors Python's ``artifact_dir_for`` so
    /// the SDKs land each artifact at identical on-disk paths.
    public nonisolated func artifactDirFor(_ artifactId: String) throws -> URL {
        guard !artifactId.isEmpty else {
            throw PrepareError.invalidInput("Refusing to prepare artifact with empty artifact_id.")
        }
        let key: String
        do {
            key = try safeFilesystemKey(artifactId)
        } catch {
            throw PrepareError.invalidInput("artifact_id is not a valid filesystem key: \(error)")
        }
        return cacheDir.appendingPathComponent(key)
    }

    /// Materialize a candidate's bytes on disk and return a
    /// ``PrepareOutcome``. Throws on unpreparable candidates,
    /// policy violations, or download exhaustion.
    public func prepare(_ candidate: PrepareCandidate, mode: PrepareMode = .lazy) async throws -> PrepareOutcome {
        try Self.validateForPrepare(candidate)
        try Self.checkExplicitOnlyVsMode(candidate, mode: mode)

        if !candidate.prepareRequired {
            return PrepareOutcome(
                artifactId: Self.artifactId(of: candidate),
                artifactDir: cacheDir,
                files: [:],
                engine: candidate.engine,
                deliveryMode: candidate.deliveryMode,
                preparePolicy: candidate.preparePolicy,
                cached: true
            )
        }
        guard var artifact = candidate.artifact else {
            throw PrepareError.invalidInput(
                "Candidate marks prepareRequired=true but carries no artifact plan. " +
                    "This is a server contract violation; refusing to prepare."
            )
        }
        // PR C-followup option 2.
        artifact = try expandStaticRecipeSource(artifact)

        let descriptor = try Self.buildDescriptor(from: artifact)
        let dir = try artifactDirFor(descriptor.artifactId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let cached = try await Self.alreadyVerified(descriptor, in: dir) {
            return PrepareOutcome(
                artifactId: descriptor.artifactId,
                artifactDir: dir,
                files: cached,
                engine: candidate.engine,
                deliveryMode: candidate.deliveryMode,
                preparePolicy: candidate.preparePolicy,
                cached: true
            )
        }

        let result = try await downloader.download(descriptor: descriptor, destDir: dir)
        return PrepareOutcome(
            artifactId: descriptor.artifactId,
            artifactDir: dir,
            files: result.files,
            engine: candidate.engine,
            deliveryMode: candidate.deliveryMode,
            preparePolicy: candidate.preparePolicy,
            cached: false
        )
    }

    /// Where artifacts live by default. Mirrors Python's
    /// ``ArtifactCache._default_cache_dir``.
    public static func defaultCacheDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let root = env["OCTOMIL_CACHE_DIR"] {
            return URL(fileURLWithPath: root).appendingPathComponent("artifacts")
        }
        if let xdg = env["XDG_CACHE_HOME"] {
            return URL(fileURLWithPath: xdg)
                .appendingPathComponent("octomil")
                .appendingPathComponent("artifacts")
        }
        // ``Library/Caches`` is the iOS-blessed cache location;
        // outside that platform we fall back to ``~/.cache/octomil``
        // for parity with Python / Node.
        #if os(iOS) || os(tvOS) || os(watchOS)
            if let caches = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
                return caches.appendingPathComponent("octomil").appendingPathComponent("artifacts")
            }
        #endif
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".cache")
            .appendingPathComponent("octomil")
            .appendingPathComponent("artifacts")
    }

    // MARK: - Validation

    private static func validateForPrepare(_ candidate: PrepareCandidate) throws {
        guard candidate.locality == "local" else {
            throw PrepareError.invalidInput("Candidate locality is \(candidate.locality.debugDescription); only \"local\" candidates are preparable.")
        }
        guard candidate.deliveryMode == "sdk_runtime" else {
            throw PrepareError.invalidInput("Candidate deliveryMode is \(candidate.deliveryMode.debugDescription); only \"sdk_runtime\" is preparable.")
        }
        if candidate.preparePolicy == .disabled {
            throw PrepareError.invalidInput("Candidate preparePolicy is .disabled; refusing to prepare.")
        }
        guard candidate.prepareRequired else { return }
        guard let artifact = candidate.artifact else {
            throw PrepareError.invalidInput("Candidate has prepareRequired=true but no artifact plan.")
        }
        guard let digest = artifact.digest, !digest.isEmpty else {
            throw PrepareError.invalidInput("Artifact '\(artifact.artifactId ?? artifact.modelId)' is missing 'digest'; refusing to prepare without integrity.")
        }
        guard !artifact.downloadUrls.isEmpty else {
            // ``source="static_recipe"`` lets the planner skip
            // downloadUrls; ``expandStaticRecipeSource`` populates
            // them. Allow that case through so the expansion can run.
            if artifact.source == "static_recipe" { return }
            throw PrepareError.invalidInput("Artifact '\(artifact.artifactId ?? artifact.modelId)' has no downloadUrls. Cannot prepare; the planner must emit at least one endpoint.")
        }
        if artifact.requiredFiles.count > 1, artifact.manifestUri == nil {
            throw PrepareError.invalidInput("Artifact '\(artifact.artifactId ?? artifact.modelId)' lists \(artifact.requiredFiles.count) requiredFiles but the planner emitted no manifestUri. The single artifact-level digest cannot verify multiple files.")
        }
        if artifact.requiredFiles.count == 1 {
            _ = try DurableDownloader.validateRelativePath(artifact.requiredFiles[0])
        }
        let id = artifact.artifactId ?? artifact.modelId
        if id.isEmpty {
            throw PrepareError.invalidInput("Refusing to prepare artifact with empty artifact_id.")
        }
        if id.contains("\u{0000}") {
            throw PrepareError.invalidInput("artifact_id contains a NUL byte: \(id.debugDescription)")
        }
    }

    private static func checkExplicitOnlyVsMode(_ candidate: PrepareCandidate, mode: PrepareMode) throws {
        if candidate.preparePolicy == .explicitOnly, mode == .lazy {
            throw PrepareError.invalidInput("Candidate has preparePolicy=.explicitOnly; refusing to prepare lazily. Use mode: .explicit (or the SDK's explicit prepare entry point).")
        }
    }

    // MARK: - Static recipe expansion

    /// PR C-followup option 2. The Swift SDK does not yet ship a
    /// recipe table of its own; expansion delegates to a host-
    /// provided recipe lookup if one is registered, otherwise the
    /// candidate is passed through unchanged. Servers that emit
    /// ``source="static_recipe"`` for an unregistered ``recipeId``
    /// will hit the downstream missing-downloadUrls branch with a
    /// clear actionable error.
    private nonisolated func expandStaticRecipeSource(_ artifact: PrepareArtifactPlan) throws -> PrepareArtifactPlan {
        guard let source = artifact.source else { return artifact }
        if source != "static_recipe" {
            throw PrepareError.invalidInput("Artifact source \(source.debugDescription) is not recognized by this SDK release. Known sources: 'static_recipe'.")
        }
        guard let recipeId = artifact.recipeId, !recipeId.isEmpty else {
            throw PrepareError.invalidInput("Artifact has source='static_recipe' but no recipeId.")
        }
        guard let recipe = StaticRecipeRegistry.shared.recipe(for: recipeId) else {
            throw PrepareError.unknownRecipe("Artifact source='static_recipe' but recipeId \(recipeId.debugDescription) is not in this SDK's registered recipe table.")
        }
        // Cross-checks: planner-supplied digest / requiredFiles MUST
        // agree with the recipe. Mismatches mean the server is asking
        // us to use a different artifact under a known recipe id —
        // refuse rather than silently substitute.
        if let plannerDigest = artifact.digest, plannerDigest != recipe.file.digest {
            throw PrepareError.checksumMismatch("Static recipe \(recipeId.debugDescription) digest \(recipe.file.digest.debugDescription) does not match planner-declared digest \(plannerDigest.debugDescription).")
        }
        if !artifact.requiredFiles.isEmpty, artifact.requiredFiles != [recipe.file.relativePath] {
            throw PrepareError.invalidInput("Static recipe \(recipeId.debugDescription) ships file \(recipe.file.relativePath.debugDescription); planner-declared requiredFiles \(artifact.requiredFiles) does not match.")
        }
        return PrepareArtifactPlan(
            modelId: artifact.modelId,
            artifactId: artifact.artifactId ?? recipe.modelId,
            digest: recipe.file.digest,
            sizeBytes: artifact.sizeBytes ?? recipe.file.sizeBytes,
            requiredFiles: [recipe.file.relativePath],
            downloadUrls: [ArtifactDownloadEndpoint(url: recipe.file.url, headers: ["X-Octomil-Recipe-Path": recipe.file.relativePath])],
            manifestUri: nil,
            source: nil,
            recipeId: nil
        )
    }

    // MARK: - Descriptor / cache

    private static func artifactId(of candidate: PrepareCandidate) -> String {
        candidate.artifact?.artifactId ?? candidate.artifact?.modelId ?? ""
    }

    private static func buildDescriptor(from artifact: PrepareArtifactPlan) throws -> ArtifactDescriptor {
        let endpoints: [DownloadEndpoint] = artifact.downloadUrls.map {
            DownloadEndpoint(url: $0.url, expiresAt: $0.expiresAt, headers: $0.headers)
        }
        let id = artifact.artifactId ?? artifact.modelId
        guard let digest = artifact.digest else {
            throw PrepareError.invalidInput("Artifact '\(id)' has no digest.")
        }
        let required: [RequiredFile]
        if artifact.requiredFiles.count == 1 {
            let rel = try DurableDownloader.validateRelativePath(artifact.requiredFiles[0])
            required = [RequiredFile(relativePath: rel, digest: digest, sizeBytes: artifact.sizeBytes)]
        } else if artifact.requiredFiles.isEmpty {
            required = [RequiredFile(relativePath: "", digest: digest, sizeBytes: artifact.sizeBytes)]
        } else {
            // Multi-file with manifest_uri — full implementation is a
            // follow-up (mirrors the Python branch); for now reject
            // loudly so the server cannot silently broadcast one
            // digest across files.
            throw PrepareError.invalidInput("Multi-file artifacts via manifestUri are not yet implemented in the Swift SDK; restrict to single-file plans for now.")
        }
        return ArtifactDescriptor(artifactId: id, requiredFiles: required, endpoints: endpoints)
    }

    private static func alreadyVerified(_ descriptor: ArtifactDescriptor, in dir: URL) async throws -> [String: URL]? {
        var verified: [String: URL] = [:]
        for required in descriptor.requiredFiles {
            let target: URL
            if required.relativePath.isEmpty {
                target = dir.appendingPathComponent("artifact")
            } else {
                target = try DurableDownloader.safeJoin(destDir: dir, relativePath: required.relativePath)
            }
            guard FileManager.default.fileExists(atPath: target.path) else { return nil }
            if try await !DurableDownloader.digestMatches(filePath: target, expected: required.digest) {
                return nil
            }
            verified[required.relativePath] = target
        }
        return verified
    }
}

// MARK: - StaticRecipeRegistry

public struct StaticRecipeFile: Sendable {
    public let relativePath: String
    public let url: URL
    public let digest: String
    public let sizeBytes: Int64?

    public init(relativePath: String, url: URL, digest: String, sizeBytes: Int64? = nil) {
        self.relativePath = relativePath
        self.url = url
        self.digest = digest
        self.sizeBytes = sizeBytes
    }
}

public struct StaticRecipe: Sendable {
    public let modelId: String
    public let file: StaticRecipeFile

    public init(modelId: String, file: StaticRecipeFile) {
        self.modelId = modelId
        self.file = file
    }
}

/// In-process registry of static recipes the SDK is willing to
/// expand under ``source="static_recipe"``. The host registers the
/// recipe ids it supports at startup; PR C-followup option 2's
/// trust contract is enforced by ``PrepareManager.expandStatic-
/// RecipeSource`` (digest / file-list cross-check). The default
/// registry includes Kokoro v0.19, mirroring Python.
public final class StaticRecipeRegistry: @unchecked Sendable {
    public static let shared = StaticRecipeRegistry()

    private let lock = NSLock()
    private var recipes: [String: StaticRecipe]

    private init() {
        // Match Python's ``static_recipes._RECIPES`` for the canonical
        // Kokoro v0.19 single-tarball recipe so iOS reads the same
        // bytes a Python-side ``client.prepare(kokoro-82m,
        // capability='tts')`` writes into the shared cache root.
        let kokoroFile = StaticRecipeFile(
            relativePath: "kokoro-en-v0_19.tar.bz2",
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models")!,
            digest: "sha256:912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7"
        )
        let kokoro = StaticRecipe(modelId: "kokoro-82m", file: kokoroFile)
        self.recipes = [
            "kokoro-82m": kokoro,
            "kokoro-en-v0_19": kokoro,
        ]
    }

    /// Register or replace a recipe at the given id.
    public func register(_ recipe: StaticRecipe, under id: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        recipes[id ?? recipe.modelId] = recipe
    }

    public func recipe(for id: String) -> StaticRecipe? {
        lock.lock()
        defer { lock.unlock() }
        return recipes[id]
    }
}

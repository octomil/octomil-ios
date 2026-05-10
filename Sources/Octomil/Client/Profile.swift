// SDK environment profile resolution — staging vs production vs dev.
//
// A *profile* names a deployment environment of the Octomil control
// plane. This module is the single source of truth in the iOS SDK for:
//
// - which base URL the SDK talks to by default,
// - which cache namespace planner / capability results are stored under,
// - which model artifact bucket the SDK expects presigned URLs to point at.
//
// Profiles let the same SDK build talk to staging or production without
// risk of cross-contamination — production cached planner decisions never
// leak into staging runs and vice-versa, because the cache key is
// namespaced by profile.
//
// Resolution order (first non-empty wins):
//
//   1. Explicit `profile` argument.
//   2. `OCTOMIL_PROFILE` ProcessInfo environment variable
//      (`staging`, `production`, `dev`, or aliases `prod`/`stg`).
//   3. Heuristic: if `OCTOMIL_API_BASE` / `OCTOMIL_API_URL` host
//      matches a known profile marker, infer that profile.
//   4. Default `production`.
//
// The values here are duplicated from
// `octomil-contracts/fixtures/core/environment_capability_manifest.json`;
// once the contracts package is published as a Swift module the SDK
// will import the canonical loader. Until then, **any change to the
// profile→base_url mapping here MUST be mirrored in the contracts
// manifest, the Python SDK, the Node SDK, and the browser SDK** or
// the promotion gate detects drift.
//
// Mirrors `octomil-python/octomil/config/profile.py`,
// `octomil-node/src/profile.ts`, and `octomil-browser/src/profile.ts`
// shape and resolution order — keep them in lockstep.

import Foundation

/// Named SDK environment profiles.
public enum OctomilProfile: String, CaseIterable, Sendable {
    case production
    case staging
    case dev

    /// Case-insensitive lookup with helpful error.
    /// Accepts ``prod`` / ``stg`` aliases that operators commonly type.
    public static func from(_ raw: String) throws -> OctomilProfile {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OctomilProfileError.invalid("profile name must be non-empty")
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [String: String] = [
            "prod": "production",
            "stg": "staging",
            "staging-2": "staging",
        ]
        let resolved = aliases[normalized] ?? normalized
        if let p = OctomilProfile(rawValue: resolved) {
            return p
        }
        let valid = OctomilProfile.allCases.map(\.rawValue).joined(separator: ", ")
        throw OctomilProfileError.invalid("unknown profile '\(raw)'; valid: \(valid)")
    }
}

public enum OctomilProfileError: Error, Equatable {
    case invalid(String)
}

/// The result of resolving a profile, with provenance.
///
/// ``source`` tells the caller HOW the profile was picked — useful for
/// logging when the SDK boots so operators can verify the right path
/// was taken (vs. silently defaulting to production).
public struct OctomilProfileResolution: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case explicit
        case env
        case urlInferred = "url_inferred"
        case `default`
    }

    public let profile: OctomilProfile
    public let source: Source

    public init(profile: OctomilProfile, source: Source) {
        self.profile = profile
        self.source = source
    }
}

public enum OctomilProfileResolver {
    // Source of truth for SDK base URLs per profile. Mirrors
    // environment_capability_manifest.json.
    //
    // Two URL forms exposed: host-only (composes its own /api/... paths)
    // and /v1-suffixed (older clients that prepend /v1).
    static let hostURLs: [OctomilProfile: String] = [
        .production: "https://api.octomil.com",
        .staging: "https://api.staging.octomil.com",
        .dev: "http://localhost:8000",
    ]

    static let v1URLs: [OctomilProfile: String] = [
        .production: "https://api.octomil.com/v1",
        .staging: "https://api.staging.octomil.com/v1",
        .dev: "http://localhost:8000/v1",
    ]

    static let artifactBuckets: [OctomilProfile: String] = [
        .production: "octomil-models",
        .staging: "octomil-models-staging",
        .dev: "octomil-models-dev",
    ]

    // Exact-host markers used for URL inference. Match is against the
    // *parsed hostname*, never a substring of the raw URL — a hostile
    // URL like https://evil.test/?next=api.staging.octomil.com or
    // api.octomil.com.evil.test MUST NOT spoof a profile.
    static let hostInferenceMarkers: [(OctomilProfile, Set<String>)] = [
        (.staging, ["api.staging.octomil.com"]),
        (.production, ["api.octomil.com"]),
        (.dev, ["localhost", "127.0.0.1", "0.0.0.0"]),
    ]

    /// Canonical SDK host URL for the given profile (no /v1 suffix).
    public static func hostURL(for profile: OctomilProfile) -> URL {
        guard let raw = hostURLs[profile], let url = URL(string: raw) else {
            preconditionFailure("OctomilProfile \(profile.rawValue) missing from hostURLs table")
        }
        return url
    }

    /// Canonical SDK base URL with /v1 suffix.
    public static func baseURLV1(for profile: OctomilProfile) -> URL {
        guard let raw = v1URLs[profile], let url = URL(string: raw) else {
            preconditionFailure("OctomilProfile \(profile.rawValue) missing from v1URLs table")
        }
        return url
    }

    /// Canonical R2 bucket for model artifacts in the given profile.
    /// Crashes (preconditionFailure) on table drift — falling back to
    /// the prod bucket would risk cross-env artifact leakage (codex
    /// post-debate B2).
    public static func artifactBucket(for profile: OctomilProfile) -> String {
        guard let bucket = artifactBuckets[profile] else {
            preconditionFailure(
                "OctomilProfile \(profile.rawValue) missing from artifactBuckets table"
            )
        }
        return bucket
    }

    /// Cache key prefix for planner/capability caches — prevents
    /// cross-environment poisoning.
    public static func cacheNamespace(for profile: OctomilProfile) -> String {
        "oct.\(profile.rawValue)"
    }

    /// Resolve the active SDK profile.
    ///
    /// - Parameters:
    ///   - profile: Explicit profile name. Wins over env / URL inference.
    ///   - environment: ProcessInfo-style env dict. Defaults to
    ///     ``ProcessInfo.processInfo.environment``. Tests inject custom
    ///     dicts to avoid global state.
    public static func resolveProfile(
        profile explicit: String? = nil,
        environment: [String: String]? = nil
    ) throws -> OctomilProfileResolution {
        let env = environment ?? ProcessInfo.processInfo.environment

        // 1. Explicit argument wins.
        if let raw = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return OctomilProfileResolution(profile: try OctomilProfile.from(raw), source: .explicit)
        }

        // 2. OCTOMIL_PROFILE env var.
        let rawEnv = (env["OCTOMIL_PROFILE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawEnv.isEmpty {
            return OctomilProfileResolution(profile: try OctomilProfile.from(rawEnv), source: .env)
        }

        // 3. URL inference. Trim BEFORE selecting so a whitespace
        //    OCTOMIL_API_BASE doesn't mask a valid OCTOMIL_API_URL
        //    (codex post-debate N1).
        let baseTrimmed = (env["OCTOMIL_API_BASE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let urlTrimmed = (env["OCTOMIL_API_URL"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitURL = baseTrimmed.isEmpty ? urlTrimmed : baseTrimmed
        if let inferred = inferFromURL(explicitURL) {
            return OctomilProfileResolution(profile: inferred, source: .urlInferred)
        }

        // 4. Default.
        return OctomilProfileResolution(profile: .production, source: .default)
    }

    /// Pick the host-only base URL the SDK should talk to.
    ///
    /// Explicit `baseURL` wins (back-compat for SDK users with custom
    /// URLs); otherwise resolves via the profile.
    public static func resolveHostURL(
        baseURL: URL? = nil,
        profile: String? = nil,
        environment: [String: String]? = nil
    ) throws -> URL {
        if let baseURL { return baseURL }
        let resolution = try resolveProfile(profile: profile, environment: environment)
        return hostURL(for: resolution.profile)
    }

    /// With /v1 suffix.
    public static func resolveBaseURLV1(
        baseURL: URL? = nil,
        profile: String? = nil,
        environment: [String: String]? = nil
    ) throws -> URL {
        if let baseURL { return baseURL }
        let resolution = try resolveProfile(profile: profile, environment: environment)
        return baseURLV1(for: resolution.profile)
    }

    private static func inferFromURL(_ raw: String) -> OctomilProfile? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Use URLComponents to parse; substring matching the raw URL
        // would let evil.test/?next=api.staging.octomil.com or
        // api.octomil.com.evil.test spoof a profile (codex post-
        // debate B1).
        guard
            let components = URLComponents(string: trimmed),
            let host = components.host?.lowercased(),
            !host.isEmpty
        else {
            return nil
        }
        for (profile, markers) in hostInferenceMarkers where markers.contains(host) {
            return profile
        }
        return nil
    }
}

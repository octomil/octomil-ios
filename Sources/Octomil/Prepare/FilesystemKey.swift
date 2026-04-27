// Shared filesystem-key helper for planner-supplied identifiers.
//
// Port of Python ``octomil/runtime/lifecycle/_fs_key.py`` and the
// Node ``src/prepare/fs-key.ts``. PrepareManager (artifact dir) and
// FileLock (lock file) consume the same key shape so two layers of
// the prepare-lifecycle pipeline cannot disagree about safety. This
// file is the one place that decides.
//
// Key requirements (mirrored across the three SDKs):
//
//   - **Bounded byte length.** ``NAME_MAX`` is 255 *bytes* on every
//     common filesystem (APFS, ext4, NTFS), not 255 characters.
//     A naive char-count cap admits filenames many times over
//     NAME_MAX once non-ASCII is involved (one emoji is up to 4
//     bytes UTF-8). The visible portion is therefore capped at
//     ``maxVisibleChars`` *characters* of pure-ASCII output (the
//     sanitizer replaces every non-ASCII byte with ``_`` first).
//   - **Windows-safe.** Strips ``< > : " / \ | ? *`` along with
//     everything non-ASCII. Even though iOS/macOS don't enforce
//     these, an artifact id round-tripped through a Windows host
//     (CI, shared NAS, code-review tools) must remain a valid
//     filename everywhere.
//   - **Stable mapping.** Same input → same output; cache hits
//     reproducible across processes and across SDKs (Python / Node /
//     Swift must pick the same key for the same artifact id, so a
//     Python-side ``client.prepare`` populates a directory that an
//     iOS-side dispatch reads).
//   - **Disambiguating.** Distinct planner ids that sanitize to the
//     same visible name still get distinct keys via a SHA-256
//     suffix taken over the *original* (unmodified) input.

import CryptoKit
import Foundation

/// Visible-portion cap. The full key is ``<visible>-<12-char hash>``;
/// 96 + 1 + 12 = 109-byte ASCII payload, well under NAME_MAX (255
/// bytes) even with the consumer's own suffix (e.g. ``.lock``).
public let DEFAULT_MAX_VISIBLE_CHARS = 96

public enum FilesystemKeyError: Error, CustomStringConvertible {
    case nulByte

    public var description: String {
        switch self {
        case .nulByte:
            return "filesystem key must not contain NUL bytes"
        }
    }
}

/// Return a NAME_MAX-safe, Windows-safe, deterministic key for
/// ``name``. Pure ASCII output, ``result.count <= maxVisibleChars +
/// 13``, stable across processes. Empty / dot-only inputs collapse
/// to ``"id"`` plus the hash suffix so the consumer always has at
/// least a 14-character (1 + 1 + 12) component.
///
/// Throws ``FilesystemKeyError.nulByte`` only when ``name`` contains
/// a NUL byte. Every other structurally-invalid input (absolute
/// paths, traversal, Windows reserved chars, non-UTF-8 surrogates)
/// sanitizes safely.
public func safeFilesystemKey(
    _ name: String,
    maxVisibleChars: Int = DEFAULT_MAX_VISIBLE_CHARS
) throws -> String {
    if name.contains("\u{0000}") {
        throw FilesystemKeyError.nulByte
    }
    var sanitized = sanitizeAscii(name)
    sanitized = stripUnderscoresDots(sanitized)
    if sanitized.isEmpty || sanitized == "." || sanitized == ".." {
        sanitized = "id"
    }
    if sanitized.count > maxVisibleChars {
        sanitized = String(sanitized.prefix(maxVisibleChars))
        sanitized = stripUnderscoresDots(sanitized)
        if sanitized.isEmpty {
            sanitized = "id"
        }
    }
    let digestPrefix = sha256HexPrefix(name, prefixCount: 12)
    return "\(sanitized)-\(digestPrefix)"
}

// MARK: - Internals

/// Replace any character outside ``[A-Za-z0-9._-]`` with ``_``.
/// Mirror of Python's ``re.compile(r"[^A-Za-z0-9._-]")``.
private func sanitizeAscii(_ value: String) -> String {
    var out = ""
    out.reserveCapacity(value.count)
    for scalar in value.unicodeScalars {
        let code = scalar.value
        let isUpper = (code >= 0x41 && code <= 0x5A)
        let isLower = (code >= 0x61 && code <= 0x7A)
        let isDigit = (code >= 0x30 && code <= 0x39)
        let isAllowed = isUpper || isLower || isDigit
            || code == 0x2E /* . */ || code == 0x2D /* - */ || code == 0x5F /* _ */
        out.append(isAllowed ? Character(scalar) : "_")
    }
    return out
}

/// Strip leading and trailing ``_`` and ``.`` runs. Used twice — once
/// after substitution, once after truncation — to mirror Python's
/// ``.strip("_.")`` semantics exactly.
private func stripUnderscoresDots(_ value: String) -> String {
    var start = value.startIndex
    while start < value.endIndex, value[start] == "_" || value[start] == "." {
        start = value.index(after: start)
    }
    var end = value.endIndex
    while end > start {
        let prev = value.index(before: end)
        let ch = value[prev]
        if ch != "_" && ch != "." { break }
        end = prev
    }
    return String(value[start ..< end])
}

/// Return the first ``prefixCount`` hex chars of SHA-256(name) over
/// the UTF-8 bytes. Matches Python's
/// ``hashlib.sha256(name.encode("utf-8", errors="surrogatepass"))``
/// for all valid Unicode inputs (Swift's ``String.utf8`` does not
/// produce lone surrogates, so the surrogatepass branch is unreachable
/// across the contract surface).
private func sha256HexPrefix(_ value: String, prefixCount: Int) -> String {
    let data = Data(value.utf8)
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(prefixCount))
}

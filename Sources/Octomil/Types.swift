// HAND-MAINTAINED — NOT auto-generated.
//
// Despite the historical name, this is a hand-owned compatibility shim, not
// swift-openapi-generator output. It defines custom types the SDK facade
// depends on (e.g. `_OctomilAPIErrorPayload`) that the generator does not
// emit. iOS does not currently consume a generated swift-openapi client;
// adopting one is a separate migration (facade rework against the 1.12.2
// output), tracked separately. Do NOT regenerate over this file.
//
// The contract spec copy lives at Sources/Octomil/openapi.yaml and is
// freshness-gated by .github/workflows/openapi-types-fresh.yml.

import OpenAPIRuntime
import Foundation

// MARK: - Generated API error payload
//
// Matches `#/components/schemas/ErrorPayload` in the Octomil OpenAPI contract.
// This type bridges API error responses to OctomilError via
// OctomilError.from(apiPayload:).

/// An error payload returned by the Octomil API in the response body.
internal struct _OctomilAPIErrorPayload: Codable, Sendable {
    /// The canonical error code string (maps to `ErrorCode` raw value).
    internal let code: String
    /// Human-readable error message.
    internal let message: String
    /// Optional retry-after duration in milliseconds.
    internal let retry_after_ms: Int64?

    internal init(code: String, message: String, retry_after_ms: Int64? = nil) {
        self.code = code
        self.message = message
        self.retry_after_ms = retry_after_ms
    }
}

// HAND-MAINTAINED — NOT auto-generated.
//
// Custom error-payload type the SDK facade depends on. The generated
// swift-openapi client (Sources/Octomil/GeneratedSources/) emits the
// contract's `ErrorEnvelope` schema, whose nested `error` object carries
// `{code, message, details}`. The SDK's error bridge instead works in terms
// of `{code, message, retry_after_ms}` — a deliberate reshape (retry_after_ms
// is surfaced to OctomilError.retryAfterMs; the wire `details` map is not).
// Because this reshapes rather than passes through, it stays hand-owned per
// the sdk_facade_vs_generated_binding_rule convention rather than binding to
// Components.Schemas.ErrorEnvelope.
//
// Consumed by OctomilError.from(apiPayload:) in OctomilError.swift.

import Foundation

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

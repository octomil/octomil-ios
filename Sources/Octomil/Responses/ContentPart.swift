import Foundation

/// A part of multimodal content within an ``InputItem``.
public enum ContentPart: Sendable {
    case text(String)
    case image(data: String?, url: String?, mediaType: String?, detail: String)
    case audio(data: String, mediaType: String)
    case file(data: String, mediaType: String, filename: String?)

    /// Convenience for creating a text content part.
    public static func text(_ value: String) -> ContentPart {
        .text(value)
    }

    /// Convenience for creating an image from base64 data.
    public static func imageData(_ data: String, mediaType: String = "image/png", detail: String = "auto") -> ContentPart {
        .image(data: data, url: nil, mediaType: mediaType, detail: detail)
    }

    /// Convenience for creating an image from a URL.
    public static func imageURL(_ url: String, detail: String = "auto") -> ContentPart {
        .image(data: nil, url: url, mediaType: nil, detail: detail)
    }
}

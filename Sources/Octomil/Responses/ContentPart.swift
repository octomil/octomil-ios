import Foundation

/// A part of multimodal content within an ``InputItem``.
public enum ContentPart: Sendable, Codable {
    case text(String)
    case image(data: String?, url: String?, mediaType: String?, detail: String)
    case audio(data: String, mediaType: String)
    case file(data: String, mediaType: String, filename: String?)

    /// Convenience for creating an image from base64 data.
    public static func imageData(_ data: String, mediaType: String = "image/png", detail: String = "auto") -> ContentPart {
        .image(data: data, url: nil, mediaType: mediaType, detail: detail)
    }

    /// Convenience for creating an image from a URL.
    public static func imageURL(_ url: String, detail: String = "auto") -> ContentPart {
        .image(data: nil, url: url, mediaType: nil, detail: detail)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type, text, data, url, mediaType = "media_type", detail, filename
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "image":
            self = .image(
                data: try c.decodeIfPresent(String.self, forKey: .data),
                url: try c.decodeIfPresent(String.self, forKey: .url),
                mediaType: try c.decodeIfPresent(String.self, forKey: .mediaType),
                detail: try c.decodeIfPresent(String.self, forKey: .detail) ?? "auto"
            )
        case "audio":
            self = .audio(
                data: try c.decode(String.self, forKey: .data),
                mediaType: try c.decode(String.self, forKey: .mediaType)
            )
        case "file":
            self = .file(
                data: try c.decode(String.self, forKey: .data),
                mediaType: try c.decode(String.self, forKey: .mediaType),
                filename: try c.decodeIfPresent(String.self, forKey: .filename)
            )
        default:
            self = .text("[unsupported type: \(type)]")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .image(let data, let url, let mediaType, let detail):
            try c.encode("image", forKey: .type)
            try c.encodeIfPresent(data, forKey: .data)
            try c.encodeIfPresent(url, forKey: .url)
            try c.encodeIfPresent(mediaType, forKey: .mediaType)
            try c.encode(detail, forKey: .detail)
        case .audio(let data, let mediaType):
            try c.encode("audio", forKey: .type)
            try c.encode(data, forKey: .data)
            try c.encode(mediaType, forKey: .mediaType)
        case .file(let data, let mediaType, let filename):
            try c.encode("file", forKey: .type)
            try c.encode(data, forKey: .data)
            try c.encode(mediaType, forKey: .mediaType)
            try c.encodeIfPresent(filename, forKey: .filename)
        }
    }
}

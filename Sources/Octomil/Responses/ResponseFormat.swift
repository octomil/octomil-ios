import Foundation

/// Constrains the format of the model's output.
public enum ResponseFormat: Sendable {
    case text
    case jsonObject
    case jsonSchema(String)
}

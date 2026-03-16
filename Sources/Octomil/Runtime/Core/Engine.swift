import Foundation

/// Inference engine for model execution.
public enum Engine: String, Sendable, Codable {
    case auto
    case coreml
    case mlx
    case llamaCpp = "llama_cpp"
}

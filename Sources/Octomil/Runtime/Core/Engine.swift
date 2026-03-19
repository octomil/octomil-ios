import Foundation

/// Inference engine for model execution.
public enum Engine: String, Sendable, Codable {
    case auto
    case coreml
    case mlx
    case llamaCpp = "llama_cpp"
    case sherpa
    case whisper

    /// Create an ``Engine`` from an executor string, handling common aliases.
    ///
    /// Executor strings come from the model catalog (e.g. `"sherpa-onnx"`,
    /// `"llama.cpp"`, `"whisper.cpp"`). This normalises them to the
    /// canonical ``Engine`` case.
    public init?(executor: String) {
        switch executor.lowercased() {
        case "sherpa", "sherpa-onnx":
            self = .sherpa
        case "whisper", "whisper.cpp":
            self = .whisper
        case "llama.cpp", "llamacpp", "llama_cpp":
            self = .llamaCpp
        case "mlx":
            self = .mlx
        case "coreml":
            self = .coreml
        default:
            return nil
        }
    }
}

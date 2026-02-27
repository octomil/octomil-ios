import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil

@available(iOS 17.0, macOS 14.0, *)
extension Deploy {

    /// Deploy an MLX model from a local directory.
    ///
    /// The directory must contain `config.json` and safetensors weights.
    /// - Parameters:
    ///   - url: Path to the MLX model directory.
    ///   - name: Human-readable name. Defaults to the directory name.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    ///   - temperature: Sampling temperature (default: 0.7).
    /// - Returns: An ``MLXDeployedModel`` ready for inference.
    public static func mlxModel(
        at url: URL,
        name: String? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.7
    ) async throws -> MLXDeployedModel {
        let resolvedName = name ?? url.lastPathComponent
        let loader = MLXModelLoader()
        let container = try await loader.loadModel(from: url)

        return MLXDeployedModel(
            name: resolvedName,
            modelContainer: container,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    /// Deploy an MLX model from HuggingFace Hub (for development/testing).
    ///
    /// - Parameters:
    ///   - modelId: HuggingFace model ID (e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit").
    ///   - name: Human-readable name. Defaults to the model ID.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    ///   - temperature: Sampling temperature (default: 0.7).
    /// - Returns: An ``MLXDeployedModel`` ready for inference.
    public static func mlxModelFromHub(
        modelId: String,
        name: String? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.7
    ) async throws -> MLXDeployedModel {
        let resolvedName = name ?? modelId
        let loader = MLXModelLoader()
        let container = try await loader.loadFromHub(modelId: modelId)

        return MLXDeployedModel(
            name: resolvedName,
            modelContainer: container,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }
}

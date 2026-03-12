import Foundation

extension OctomilResponses {
    /// Wire LLMRuntimeRegistry into ModelRuntimeRegistry so that
    /// `responses.create()` can use LLMRuntime implementations.
    ///
    /// Call once at app startup after setting `LLMRuntimeRegistry.shared.factory`.
    public static func connectRuntime() {
        ModelRuntimeRegistry.shared.defaultFactory = { modelId in
            guard let factory = LLMRuntimeRegistry.shared.factory else { return nil }
            // Treat modelId as a file path for now — apps that use URL-based
            // model resolution should register a family-specific factory instead.
            let url = URL(fileURLWithPath: modelId)
            let llm = factory(url)
            return LLMRuntimeAdapter(llmRuntime: llm)
        }
    }
}

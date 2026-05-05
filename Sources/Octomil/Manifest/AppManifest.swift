import Foundation

// MARK: - ModelCapability

/// Declares the capability a model provides.
///
/// Typealiased from the contract-generated `ContractModelCapability` so the
/// rest of the SDK continues to use the stable `ModelCapability` name.
public typealias ModelCapability = ContractModelCapability

// MARK: - DeliveryMode

/// How the model artifact is delivered to the device.
///
/// Typealiased from the contract-generated `ContractDeliveryMode`.
public typealias DeliveryMode = ContractDeliveryMode

// MARK: - AppRoutingPolicy

/// Per-model routing policy governing local vs. cloud inference.
///
/// Typealiased from the contract-generated `ContractRoutingPolicy`.
/// Named `AppRoutingPolicy` to avoid collision with the existing
/// `RoutingPolicy` struct in `QueryRoutingClient`.
public typealias AppRoutingPolicy = ContractRoutingPolicy

// MARK: - ModelRef

/// A reference to a model — either by catalog ID or by capability.
public enum ModelRef: Sendable {
    case id(String)
    case capability(ModelCapability)
}

// MARK: - ResourceBinding

/// Maps an ``ArtifactResourceKind`` to a file path, enabling explicit
/// multi-resource model loading without filename heuristics.
///
/// A multimodal VL model might declare:
/// ```swift
/// [
///     ResourceBinding(kind: .weights, path: "Models/llava-v1.5-7b.gguf"),
///     ResourceBinding(kind: .projector, path: "Models/llava-v1.5-7b-mmproj.gguf"),
/// ]
/// ```
public struct ResourceBinding: Sendable, Codable, Equatable {
    /// The kind of resource (weights, projector, tokenizer, etc.).
    public let kind: ArtifactResourceKind

    /// Relative path to the resource file within the model package or bundle.
    public let path: String

    public init(kind: ArtifactResourceKind, path: String) {
        self.kind = kind
        self.path = path
    }
}

// MARK: - EngineConfig

/// Executor-specific configuration hints attached to a manifest entry.
///
/// Keys and values are engine-dependent. For example, a llama.cpp VL model
/// might include `{"n_gpu_layers": "99", "mmproj": "true"}`.
///
/// This is intentionally untyped (`[String: String]`) to avoid coupling
/// the manifest schema to any specific engine version.
public typealias EngineConfig = [String: String]

// MARK: - AppModelEntry

/// A single model declaration in the app manifest.
public struct AppModelEntry: Sendable, Codable {
    /// Catalog model identifier (e.g. "phi-4-mini", "whisper-base").
    public let id: String

    /// The capability this model provides.
    public let capability: ModelCapability

    /// How the model artifact is delivered.
    public let delivery: DeliveryMode

    /// Routing policy override. When nil, a default is derived from ``delivery``.
    public let routingPolicy: AppRoutingPolicy?

    /// Relative path inside Bundle.main for ``DeliveryMode/bundled`` models.
    public let bundledPath: String?

    /// Whether the SDK should fail initialization if this model cannot be resolved.
    public let required: Bool

    /// Input modalities this model accepts (e.g. `[.text, .image]` for a VL model).
    ///
    /// When nil, defaults to `[.text]` for chat/text_completion capabilities.
    /// Modality is orthogonal to capability — a chat model that also accepts
    /// images is still `capability: .chat` with `inputModalities: [.text, .image]`.
    public let inputModalities: [InputModality]?

    /// Output modalities this model produces (e.g. `[.text]`).
    ///
    /// When nil, defaults to `[.text]`.
    public let outputModalities: [Modality]?

    /// Explicit mapping of resource kinds to file paths within the model package.
    ///
    /// When present, the runtime uses these bindings to locate model files
    /// instead of relying on filename pattern matching. This is required for
    /// multi-resource packages (e.g. weights + projector + processor).
    public let resourceBindings: [ResourceBinding]?

    /// Executor-specific configuration hints.
    ///
    /// Passed through to the engine at load time. Keys and values are
    /// engine-dependent and intentionally untyped.
    public let engineConfig: EngineConfig?

    /// Effective routing policy, derived from ``routingPolicy`` or ``delivery``.
    public var effectiveRoutingPolicy: AppRoutingPolicy {
        if let explicit = routingPolicy { return explicit }
        switch delivery {
        case .bundled:  return .localOnly
        case .managed:  return .localFirst
        case .cloud:    return .cloudOnly
        }
    }

    /// Whether this model accepts image input.
    public var supportsImageInput: Bool {
        inputModalities?.contains(.image) ?? false
    }

    /// Whether this model is multimodal (accepts more than one input modality).
    public var isMultimodal: Bool {
        guard let modalities = inputModalities else { return false }
        return modalities.count > 1
    }

    /// Resolve the file URL for a specific resource kind from ``resourceBindings``.
    ///
    /// - Parameters:
    ///   - kind: The resource kind to look up.
    ///   - baseURL: Base directory URL to resolve relative paths against.
    /// - Returns: The resolved file URL, or nil if no binding exists for this kind.
    public func resolvedURL(for kind: ArtifactResourceKind, relativeTo baseURL: URL) -> URL? {
        guard let binding = resourceBindings?.first(where: { $0.kind == kind }) else {
            return nil
        }
        return baseURL.appendingPathComponent(binding.path)
    }

    public init(
        id: String,
        capability: ModelCapability,
        delivery: DeliveryMode,
        routingPolicy: AppRoutingPolicy? = nil,
        bundledPath: String? = nil,
        required: Bool = true,
        inputModalities: [InputModality]? = nil,
        outputModalities: [Modality]? = nil,
        resourceBindings: [ResourceBinding]? = nil,
        engineConfig: EngineConfig? = nil
    ) {
        self.id = id
        self.capability = capability
        self.delivery = delivery
        self.routingPolicy = routingPolicy
        self.bundledPath = bundledPath
        self.required = required
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.resourceBindings = resourceBindings
        self.engineConfig = engineConfig
    }
}

// MARK: - AppManifest

/// Declares the models an app needs, how they should be delivered,
/// and the routing policy for each.
///
/// The manifest is pure data — it does not import APIClient, ModelManager,
/// or any runtime types. ``ModelCatalogService`` consumes it at boot time.
///
/// ```swift
/// let manifest = AppManifest(models: [
///     AppModelEntry(id: "phi-4-mini", capability: .chat, delivery: .managed),
///     AppModelEntry(id: "whisper-base", capability: .transcription, delivery: .bundled,
///                   bundledPath: "Models/whisper-base.mlmodelc"),
/// ])
/// try await client.configure(manifest: manifest)
/// ```
public struct AppManifest: Sendable, Codable {
    /// The model entries declared by the app.
    public let models: [AppModelEntry]

    public init(models: [AppModelEntry]) {
        self.models = models
    }

    /// Look up the first entry matching a capability.
    public func entry(for capability: ModelCapability) -> AppModelEntry? {
        models.first { $0.capability == capability }
    }

    /// Look up an entry by model ID.
    public func entry(forModelId id: String) -> AppModelEntry? {
        models.first { $0.id == id }
    }

    /// Look up entries that accept a given input modality.
    ///
    /// Returns all models whose ``AppModelEntry/inputModalities`` contain
    /// the requested modality, or all text-capable models if no modality
    /// metadata is present (backward-compatible default).
    public func entries(accepting modality: InputModality) -> [AppModelEntry] {
        models.filter { entry in
            if let modalities = entry.inputModalities {
                return modalities.contains(modality)
            }
            // Legacy entries without inputModalities default to text-only
            return modality == .text
        }
    }

    /// Look up entries that are multimodal (accept more than one input modality).
    public func multimodalEntries() -> [AppModelEntry] {
        models.filter { $0.isMultimodal }
    }
}

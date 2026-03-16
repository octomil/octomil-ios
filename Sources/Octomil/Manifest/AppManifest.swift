import Foundation

// MARK: - ModelCapability

/// Declares the capability a model provides.
///
/// SDK-local enum — will be replaced by codegen from octomil-contracts
/// once naming conflicts with existing types are resolved.
public enum ModelCapability: String, Sendable, Codable, Hashable {
    case chat
    case transcription
    case textCompletion = "text_completion"
    case keyboardPrediction = "keyboard_prediction"
    case embedding
    case classification
}

// MARK: - DeliveryMode

/// How the model artifact is delivered to the device.
///
/// SDK-local enum — will be replaced by codegen from octomil-contracts.
public enum DeliveryMode: String, Sendable, Codable {
    /// Model is bundled inside the app binary.
    case bundled
    /// Model is downloaded and managed by the SDK at runtime.
    case managed
    /// Model runs entirely in the cloud.
    case cloud
}

// MARK: - AppRoutingPolicy

/// Per-model routing policy governing local vs. cloud inference.
///
/// Named `AppRoutingPolicy` to avoid collision with the existing
/// `RoutingPolicy` struct in `QueryRoutingClient`.
public enum AppRoutingPolicy: String, Sendable, Codable {
    case localOnly = "local_only"
    case localFirst = "local_first"
    case cloudOnly = "cloud_only"
}

// MARK: - ModelRef

/// A reference to a model — either by catalog ID or by capability.
public enum ModelRef: Sendable {
    case id(String)
    case capability(ModelCapability)
}

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

    /// Effective routing policy, derived from ``routingPolicy`` or ``delivery``.
    public var effectiveRoutingPolicy: AppRoutingPolicy {
        if let explicit = routingPolicy { return explicit }
        switch delivery {
        case .bundled:  return .localOnly
        case .managed:  return .localFirst
        case .cloud:    return .cloudOnly
        }
    }

    public init(
        id: String,
        capability: ModelCapability,
        delivery: DeliveryMode,
        routingPolicy: AppRoutingPolicy? = nil,
        bundledPath: String? = nil,
        required: Bool = true
    ) {
        self.id = id
        self.capability = capability
        self.delivery = delivery
        self.routingPolicy = routingPolicy
        self.bundledPath = bundledPath
        self.required = required
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
}

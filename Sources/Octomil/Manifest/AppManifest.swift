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

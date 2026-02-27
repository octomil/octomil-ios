import Foundation

// MARK: - EngineResolutionError

/// Errors thrown when the ``EngineRegistry`` cannot resolve an engine.
public enum EngineResolutionError: Error, LocalizedError {
    /// No factory registered for the requested modality/engine combination.
    case noEngineRegistered(modality: Modality, engine: Engine?)

    public var errorDescription: String? {
        switch self {
        case .noEngineRegistered(let modality, let engine):
            if let engine = engine {
                return "No engine registered for modality '\(modality.rawValue)' with engine '\(engine.rawValue)'"
            }
            return "No engine registered for modality '\(modality.rawValue)'"
        }
    }
}

// MARK: - EngineRegistry

/// Thread-safe registry mapping (Modality, Engine?) pairs to engine factories.
///
/// The registry follows a two-step resolution chain:
/// 1. Exact match on `(modality, engine)`
/// 2. Fallback to modality default `(modality, nil)`
/// 3. Throw ``EngineResolutionError`` if neither exists.
///
/// Default registrations are installed at init time for all built-in modalities.
/// Extension modules (OctomilMLX, OctomilTimeSeries) can register additional
/// factories at runtime.
public final class EngineRegistry: @unchecked Sendable {

    // MARK: - Types

    /// Composite key for the factory dictionary.
    public struct EngineKey: Hashable, Sendable {
        public let modality: Modality
        public let engine: Engine?

        public init(modality: Modality, engine: Engine? = nil) {
            self.modality = modality
            self.engine = engine
        }
    }

    /// A closure that creates a ``StreamingInferenceEngine`` from a model URL.
    public typealias EngineFactory = @Sendable (URL) throws -> StreamingInferenceEngine

    // MARK: - Singleton

    /// Shared singleton instance with default registrations.
    public static let shared = EngineRegistry()

    // MARK: - State

    private let lock = NSLock()
    private var factories: [EngineKey: EngineFactory] = [:]

    // MARK: - Init

    public init() {
        registerDefaults()
    }

    // MARK: - Registration

    /// Register a factory for a given modality and optional engine.
    ///
    /// - Parameters:
    ///   - modality: The output modality.
    ///   - engine: The specific engine, or `nil` for the modality default.
    ///   - factory: Closure that creates a ``StreamingInferenceEngine`` from a model URL.
    public func register(modality: Modality, engine: Engine? = nil, factory: @escaping EngineFactory) {
        let key = EngineKey(modality: modality, engine: engine)
        lock.lock()
        defer { lock.unlock() }
        factories[key] = factory
    }

    // MARK: - Resolution

    /// Resolve a ``StreamingInferenceEngine`` for the given modality, engine, and model URL.
    ///
    /// Resolution chain:
    /// 1. Exact match `(modality, engine)` if engine is non-nil
    /// 2. Modality default `(modality, nil)`
    /// 3. Throw ``EngineResolutionError``
    ///
    /// - Parameters:
    ///   - modality: The output modality.
    ///   - engine: The specific engine (from URL inference or user choice), or `nil`.
    ///   - modelURL: URL passed to the factory to construct the engine.
    /// - Returns: A configured ``StreamingInferenceEngine``.
    /// - Throws: ``EngineResolutionError`` if no matching factory is found.
    public func resolve(modality: Modality, engine: Engine? = nil, modelURL: URL) throws -> StreamingInferenceEngine {
        lock.lock()
        let snapshot = factories
        lock.unlock()

        // 1. Exact match
        if let engine = engine {
            let exactKey = EngineKey(modality: modality, engine: engine)
            if let factory = snapshot[exactKey] {
                return try factory(modelURL)
            }
        }

        // 2. Modality default
        let defaultKey = EngineKey(modality: modality, engine: nil)
        if let factory = snapshot[defaultKey] {
            return try factory(modelURL)
        }

        // 3. No match
        throw EngineResolutionError.noEngineRegistered(modality: modality, engine: engine)
    }

    // MARK: - URL-based Engine Inference

    /// Infer the ``Engine`` from a model file's extension.
    ///
    /// - `.mlmodelc`, `.mlmodel`, `.mlpackage` -> `.coreml`
    /// - `.safetensors`, `.gguf` -> `.mlx`
    /// - Anything else -> `nil`
    public static func engineFromURL(_ url: URL) -> Engine? {
        switch url.pathExtension.lowercased() {
        case "mlmodelc", "mlmodel", "mlpackage":
            return .coreml
        case "safetensors", "gguf":
            return .mlx
        default:
            return nil
        }
    }

    // MARK: - Reset

    /// Clear all registrations and re-install defaults. Intended for testing.
    public func reset() {
        lock.lock()
        factories.removeAll()
        lock.unlock()
        registerDefaults()
    }

    /// Remove all registrations without re-installing defaults. Intended for testing.
    public func removeAllRegistrations() {
        lock.lock()
        defer { lock.unlock() }
        factories.removeAll()
    }

    // MARK: - Private

    private func registerDefaults() {
        register(modality: .text) { url in LLMEngine(modelPath: url) }
        register(modality: .image) { url in ImageEngine(modelPath: url) }
        register(modality: .audio) { url in AudioEngine(modelPath: url) }
        register(modality: .video) { url in VideoEngine(modelPath: url) }
        register(modality: .timeSeries) { url in LLMEngine(modelPath: url) }
    }
}

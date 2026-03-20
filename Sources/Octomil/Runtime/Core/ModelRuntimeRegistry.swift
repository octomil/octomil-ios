import Foundation

/// Global registry for ``ModelRuntime`` factories.
///
/// Resolution order: exact family -> prefix match -> default factory.
public final class ModelRuntimeRegistry: @unchecked Sendable {
    public static let shared = ModelRuntimeRegistry()

    private var families: [String: RuntimeFactory] = [:]
    private let lock = NSLock()

    /// Default factory used when no family matches.
    public var defaultFactory: RuntimeFactory?

    private init() {}

    /// Register a factory for a model family (e.g., "phi", "llama").
    public func register(family: String, factory: @escaping RuntimeFactory) {
        lock.lock()
        defer { lock.unlock() }
        families[family.lowercased()] = factory
    }

    /// Resolve a ``ModelRuntime`` for the given model ID.
    public func resolve(modelId: String) -> ModelRuntime? {
        lock.lock()
        let snapshot = families
        let defaultFac = defaultFactory
        lock.unlock()

        let lowered = modelId.lowercased()

        // 1. Exact family match
        if let factory = snapshot[lowered], let runtime = factory(modelId) {
            return runtime
        }

        // 2. Prefix match — longest prefix wins
        let prefix = snapshot.keys
            .filter { lowered.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        if let prefix = prefix, let factory = snapshot[prefix], let runtime = factory(modelId) {
            return runtime
        }

        // 3. Default factory
        return defaultFac?(modelId)
    }

    /// Convenience: register a ``LocalFileModelRuntime`` for a model on disk.
    ///
    /// Handles `Engine` resolution, `ArtifactResourceKind` mapping, and factory
    /// wrapping internally so callers don't need to touch those types.
    ///
    /// - Parameters:
    ///   - name: Model family name used for registry lookup.
    ///   - fileURL: Directory (or file) URL of the primary model artifact.
    ///   - engine: Explicit engine; `nil` lets the runtime infer from file extension.
    ///   - resourceBindings: String-keyed resource kind → filename dictionary
    ///     (e.g. `["tokenizer": "tokenizer.json"]`). Filenames are resolved
    ///     relative to `fileURL`.
    public func registerModel(
        name: String,
        fileURL: URL,
        engine: Engine? = nil,
        resourceBindings: [String: String] = [:]
    ) {
        var resolved: [ArtifactResourceKind: URL] = [:]
        for (kindString, filename) in resourceBindings {
            if let kind = ArtifactResourceKind(rawValue: kindString) {
                resolved[kind] = fileURL.appendingPathComponent(filename)
            }
        }
        register(family: name) { _ in
            LocalFileModelRuntime(
                modelId: name,
                fileURL: fileURL,
                resourceBindings: resolved,
                engine: engine
            )
        }
    }

    /// Remove all registrations. Primarily for testing.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        families.removeAll()
        defaultFactory = nil
    }
}

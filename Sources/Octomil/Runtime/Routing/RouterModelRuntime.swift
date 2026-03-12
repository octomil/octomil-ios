import Foundation

/// ADVANCED — MAY: Hybrid local/cloud inference router.
///
/// This is an optional advanced feature. Most applications register a single
/// ``ModelRuntime`` and do not need routing. Use ``RouterModelRuntime`` when
/// your app supports both on-device and cloud inference and you want automatic
/// or policy-driven fallback between them.
///
/// Routes inference to local or cloud runtimes based on a ``RoutingPolicy``.
///
/// Resolution order:
/// - `.localOnly`  → use local factory, throw if unavailable
/// - `.cloudOnly`  → use cloud factory, throw if unavailable
/// - `.auto`       → prefer local, fall back to cloud (or vice versa)
public final class RouterModelRuntime: ModelRuntime, @unchecked Sendable {
    private let localFactory: RuntimeFactory?
    private let cloudFactory: RuntimeFactory?
    private let defaultPolicy: InferenceRoutingPolicy

    public init(
        localFactory: RuntimeFactory? = nil,
        cloudFactory: RuntimeFactory? = nil,
        defaultPolicy: InferenceRoutingPolicy = .auto()
    ) {
        self.localFactory = localFactory
        self.cloudFactory = cloudFactory
        self.defaultPolicy = defaultPolicy
    }

    public var capabilities: RuntimeCapabilities {
        RuntimeCapabilities(supportsToolCalls: true, supportsStreaming: true)
    }

    public func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        let runtime = try selectRuntime()
        return try await runtime.run(request: request)
    }

    public func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        do {
            let runtime = try selectRuntime()
            return runtime.stream(request: request)
        } catch {
            return AsyncThrowingStream { throw error }
        }
    }

    public func close() {}

    // MARK: - Private

    private func selectRuntime() throws -> ModelRuntime {
        switch defaultPolicy {
        case .localOnly:
            guard let local = localFactory?("local") else {
                throw OctomilResponsesError.runtimeNotFound("No local runtime available")
            }
            return local
        case .cloudOnly:
            guard let cloud = cloudFactory?("cloud") else {
                throw OctomilResponsesError.runtimeNotFound("No cloud runtime available")
            }
            return cloud
        case .auto(_, _, let fallback):
            if let local = localFactory?("local") { return local }
            if fallback == "cloud", let cloud = cloudFactory?("cloud") { return cloud }
            throw OctomilResponsesError.runtimeNotFound("No runtime available")
        }
    }
}

import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import Octomil

/// Real MLX-backed LLM inference engine conforming to ``StreamingInferenceEngine``.
///
/// Uses `mlx-swift-lm`'s ``ModelContainer`` for token-by-token generation on Apple Silicon.
/// Supports KV cache prefix reuse across sequential generations sharing a common prompt prefix.
/// Requires iOS 17+ / macOS 14+.
@available(iOS 17.0, macOS 14.0, *)
public final class MLXLLMEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let modelContainer: ModelContainer
    public var maxTokens: Int
    public var temperature: Float
    public let cacheEnabled: Bool

    // KV cache pool — guarded internally by NSLock
    private let cachePool = KVCachePool(maxEntries: 4)
    private var _cacheHits: Int = 0
    private var _cacheMisses: Int = 0

    /// Number of KV cache hits since engine creation.
    public var cacheHits: Int { _cacheHits }
    /// Number of KV cache misses since engine creation.
    public var cacheMisses: Int { _cacheMisses }

    /// Creates an MLX LLM engine.
    /// - Parameters:
    ///   - modelContainer: A loaded MLX model container.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    ///   - temperature: Sampling temperature (default: 0.7).
    ///   - cacheEnabled: Whether to reuse KV caches across generations (default: true).
    public init(
        modelContainer: ModelContainer,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        cacheEnabled: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.cacheEnabled = cacheEnabled
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let prompt: String
        if let str = input as? String {
            prompt = str
        } else {
            prompt = String(describing: input)
        }

        let maxTokens = self.maxTokens
        let temperature = self.temperature
        let container = self.modelContainer
        let cacheEnabled = self.cacheEnabled

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    // Prepare input and get the generation stream inside container.perform.
                    // Also capture the cache array so we can store it for next call.
                    let (stream, cache, promptTokenIds) = try await container.perform {
                        context -> (AsyncStream<Generation>, [KVCache]?, [Int]) in

                        let prepared = try await context.processor.prepare(input: .init(prompt: prompt))
                        let promptTokenIds = context.tokenizer.encode(text: prompt)

                        let cache: [KVCache]? = cacheEnabled
                            ? self?.fetchOrCreateCache(promptTokenIds: promptTokenIds)
                            : nil

                        let genStream = try MLXLMCommon.generate(
                            input: prepared,
                            cache: cache,
                            parameters: .init(
                                maxTokens: maxTokens,
                                temperature: temperature,
                                topP: 0.9,
                                prefillStepSize: 4096
                            ),
                            context: context
                        )

                        return (genStream, cache, promptTokenIds)
                    }

                    // Iterate the generation stream outside container.perform
                    var index = 0
                    for await generation in stream {
                        if Task.isCancelled { break }

                        switch generation {
                        case .chunk(let text):
                            let data = Data(text.utf8)
                            let chunk = InferenceChunk(
                                index: index,
                                data: data,
                                modality: .text,
                                timestamp: Date(),
                                latencyMs: 0
                            )
                            continuation.yield(chunk)
                            index += 1

                        case .info, .toolCall:
                            break
                        }
                    }

                    // Store cache in pool for reuse on next generation
                    if cacheEnabled, let kvCaches = cache {
                        self?.cachePool.storeCache(
                            promptTokenIds: promptTokenIds,
                            kvCaches: kvCaches
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - KV Cache Management

    /// Look up the best matching cached prefix from the pool.
    /// If commonLen >= 4, reuse the cache with trimming. Otherwise, return nil.
    private func fetchOrCreateCache(promptTokenIds: [Int]) -> [KVCache]? {
        guard let match = cachePool.fetchCachedPrefix(promptTokenIds: promptTokenIds) else {
            _cacheMisses += 1
            return nil
        }

        let cachedKV = match.kvCaches
        let commonLen = match.commonLength

        // Trim cache: remove tokens beyond commonLen - 1 (re-process last common token).
        // KVCache.offset gives current cache length; trim(_ n:) removes n tokens from the end.
        for kv in cachedKV {
            if kv.isTrimmable {
                let excess = kv.offset - (commonLen - 1)
                if excess > 0 {
                    kv.trim(excess)
                }
            }
        }

        _cacheHits += 1
        return cachedKV
    }
}

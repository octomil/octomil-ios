import Foundation
import Octomil
import llama

/// llama.cpp inference engine conforming to ``StreamingInferenceEngine``.
///
/// Wraps the llama.cpp C API to perform token-by-token text generation
/// with Metal acceleration on Apple Silicon.
final class LlamaCppEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let modelPath: URL
    private let maxTokens: Int
    private let temperature: Float

    init(modelPath: URL, maxTokens: Int = 2048, temperature: Float = 0.7) {
        self.modelPath = modelPath
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    func generate(input: Any, modality: Modality, config: GenerationConfig) -> AsyncThrowingStream<InferenceChunk, Error> {
        let prompt: String
        if let str = input as? String {
            prompt = str
        } else if let mm = input as? MultimodalInput {
            prompt = mm.prompt
        } else {
            prompt = String(describing: input)
        }

        let path = modelPath.path
        let maxTokens = config.maxTokens
        let temperature = Float(config.temperature)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let ctx = try LlamaContext.create(path: path, temperature: temperature)
                    defer { ctx.destroy() }

                    ctx.preparePrompt(prompt)

                    if llama_decode(ctx.context, ctx.batch) != 0 {
                        throw LlamaCppError.decodeFailed
                    }

                    var index = 0
                    while index < maxTokens {
                        if Task.isCancelled { break }

                        let tokenId = llama_sampler_sample(ctx.sampling, ctx.context, ctx.batch.n_tokens - 1)

                        if llama_vocab_is_eog(ctx.vocab, tokenId) {
                            // Flush any remaining bytes
                            if let remaining = ctx.flushInvalidBytes() {
                                let chunk = InferenceChunk(
                                    index: index,
                                    data: Data(remaining.utf8),
                                    modality: .text,
                                    timestamp: Date(),
                                    latencyMs: 0
                                )
                                continuation.yield(chunk)
                            }
                            break
                        }

                        if let text = ctx.processToken(tokenId) {
                            let chunk = InferenceChunk(
                                index: index,
                                data: Data(text.utf8),
                                modality: .text,
                                timestamp: Date(),
                                latencyMs: 0
                            )
                            continuation.yield(chunk)
                            index += 1
                        }

                        // Prepare next decode
                        llama_batch_clear(&ctx.batch)
                        llama_batch_add(&ctx.batch, tokenId, ctx.nCur, [0], true)
                        ctx.nCur += 1

                        if llama_decode(ctx.context, ctx.batch) != 0 {
                            throw LlamaCppError.decodeFailed
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Errors

enum LlamaCppError: Error, LocalizedError {
    case modelLoadFailed(String)
    case contextInitFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Failed to load llama model at \(path)"
        case .contextInitFailed: return "Failed to initialize llama context"
        case .decodeFailed: return "llama_decode() failed"
        }
    }
}

// MARK: - LlamaContext (internal C wrapper)

/// Manages llama.cpp C pointers with safe lifecycle handling.
final class LlamaContext: @unchecked Sendable {
    let model: OpaquePointer
    let context: OpaquePointer
    let vocab: OpaquePointer
    let sampling: UnsafeMutablePointer<llama_sampler>
    var batch: llama_batch
    var nCur: Int32 = 0

    private var temporaryInvalidCChars: [CChar] = []

    private init(model: OpaquePointer, context: OpaquePointer, temperature: Float) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.batch = llama_batch_init(512, 0, 1)

        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
    }

    static func create(path: String, temperature: Float) throws -> LlamaContext {
        llama_backend_init()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #endif

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaCppError.modelLoadFailed(path)
        }

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaCppError.contextInitFailed
        }

        return LlamaContext(model: model, context: context, temperature: temperature)
    }

    func preparePrompt(_ text: String) {
        let tokens = tokenize(text: text, addBos: true)
        temporaryInvalidCChars = []

        llama_batch_clear(&batch)
        for (i, token) in tokens.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1
        nCur = batch.n_tokens
    }

    /// Process a newly sampled token. Returns the decoded string if valid UTF-8
    /// is available, or nil if we're still accumulating multi-byte characters.
    func processToken(_ tokenId: llama_token) -> String? {
        let cchars = tokenToPiece(token: tokenId)
        temporaryInvalidCChars.append(contentsOf: cchars)

        if let string = String(validatingUTF8: temporaryInvalidCChars + [0]) {
            temporaryInvalidCChars.removeAll()
            return string
        } else if (0..<temporaryInvalidCChars.count).contains(where: {
            $0 != 0 && String(validatingUTF8: Array(temporaryInvalidCChars.suffix($0)) + [0]) != nil
        }) {
            let string = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            return string
        }

        return nil
    }

    func flushInvalidBytes() -> String? {
        guard !temporaryInvalidCChars.isEmpty else { return nil }
        let str = String(cString: temporaryInvalidCChars + [0])
        temporaryInvalidCChars.removeAll()
        return str.isEmpty ? nil : str
    }

    func destroy() {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    // MARK: - Private

    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + (addBos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        defer { tokens.deallocate() }

        let count = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBos, false)
        return (0..<Int(count)).map { tokens[$0] }
    }

    private func tokenToPiece(token: llama_token) -> [CChar] {
        let bufSize = 8
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: bufSize)
        result.initialize(repeating: 0, count: bufSize)
        defer { result.deallocate() }

        let nTokens = llama_token_to_piece(vocab, token, result, Int32(bufSize), 0, false)

        if nTokens < 0 {
            let newSize = Int(-nTokens)
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: newSize)
            newResult.initialize(repeating: 0, count: newSize)
            defer { newResult.deallocate() }
            let n = llama_token_to_piece(vocab, token, newResult, Int32(newSize), 0, false)
            return Array(UnsafeBufferPointer(start: newResult, count: Int(n)))
        } else {
            return Array(UnsafeBufferPointer(start: result, count: Int(nTokens)))
        }
    }
}

// MARK: - C batch helpers

func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(
    _ batch: inout llama_batch,
    _ id: llama_token,
    _ pos: llama_pos,
    _ seqIds: [llama_seq_id],
    _ logits: Bool
) {
    batch.token[Int(batch.n_tokens)] = id
    batch.pos[Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seqIds.count)
    for i in 0..<seqIds.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seqIds[i]
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

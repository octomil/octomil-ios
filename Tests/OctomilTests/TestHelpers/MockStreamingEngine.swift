import Foundation
@testable import Octomil

/// A configurable mock ``StreamingInferenceEngine`` for testing.
///
/// Supply an array of ``ChunkSpec`` values to control exactly what each
/// invocation of ``generate(input:modality:)`` yields.  You can inject
/// per-chunk delays, a terminal error, or both.
final class MockStreamingEngine: StreamingInferenceEngine, @unchecked Sendable {

    /// Describes a single chunk the engine should yield.
    struct ChunkSpec: Sendable {
        let data: Data
        let delayNanoseconds: UInt64

        init(_ string: String, delayMs: Double = 0) {
            self.data = Data(string.utf8)
            self.delayNanoseconds = UInt64(delayMs * 1_000_000)
        }

        init(data: Data, delayMs: Double = 0) {
            self.data = data
            self.delayNanoseconds = UInt64(delayMs * 1_000_000)
        }
    }

    /// Chunks to yield for the next call to ``generate``.
    var chunks: [ChunkSpec] = []

    /// Optional error to throw after yielding all chunks.
    var terminalError: Error?

    /// Records every `input` received.
    private(set) var recordedInputs: [Any] = []

    /// Records every `config` received.
    private(set) var recordedConfigs: [GenerationConfig] = []

    func generate(input: Any, modality: InferenceModality, config: GenerationConfig) -> AsyncThrowingStream<InferenceChunk, Error> {
        recordedInputs.append(input)
        recordedConfigs.append(config)
        let specs = chunks
        let error = terminalError

        return AsyncThrowingStream { continuation in
            let task = Task {
                for (index, spec) in specs.enumerated() {
                    if Task.isCancelled { break }
                    if spec.delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: spec.delayNanoseconds)
                    }
                    let chunk = InferenceChunk(
                        index: index,
                        data: spec.data,
                        modality: modality,
                        timestamp: Date(),
                        latencyMs: 0
                    )
                    continuation.yield(chunk)
                }

                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

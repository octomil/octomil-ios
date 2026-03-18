import Foundation

/// Protocol for live (real-time) speech transcription.
///
/// Conforming types maintain a persistent recognizer and accept incremental
/// audio samples, producing partial transcription results as audio streams in.
///
/// # Usage
///
/// ```swift
/// let transcriber = LiveTranscriberFactory.shared.create(
///     engine: "sherpa", modelURL: modelDir)
/// try transcriber?.start()
/// transcriber?.feedSamples(audioChunk)    // call repeatedly
/// let partial = transcriber?.getPartialResult()
/// let final = transcriber?.stop()
/// ```
public protocol LiveTranscriber: AnyObject {
    /// Initializes the recognizer. Must be called before feeding samples.
    func start() throws

    /// Feeds a chunk of audio samples.
    /// - Parameter samples: PCM Float samples, 16 kHz mono, normalized [-1, 1].
    func feedSamples(_ samples: [Float])

    /// Returns the current partial transcription result.
    func getPartialResult() -> String

    /// Signals end of audio and returns the final result.
    func stop() -> String

    /// Resets the recognizer state for a new utterance.
    func reset()
}

/// Factory for creating ``LiveTranscriber`` instances.
///
/// Engine adapters register their factories during bootstrap. App code
/// resolves a transcriber by engine name and model URL.
public final class LiveTranscriberFactory: @unchecked Sendable {
    public static let shared = LiveTranscriberFactory()

    private var factories: [String: (URL) -> LiveTranscriber] = [:]
    private let lock = NSLock()

    private init() {}

    /// Register a live transcriber factory for an engine.
    public func register(engine: String, factory: @escaping (URL) -> LiveTranscriber) {
        lock.lock()
        defer { lock.unlock() }
        factories[engine.lowercased()] = factory
    }

    /// Create a live transcriber for the given engine and model URL.
    public func create(engine: String, modelURL: URL) -> LiveTranscriber? {
        lock.lock()
        defer { lock.unlock() }
        return factories[engine.lowercased()]?(modelURL)
    }
}

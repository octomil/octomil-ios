#if canImport(sherpa_onnx)
import Foundation
import Octomil
import sherpa_onnx

/// Live (real-time) speech transcription using sherpa-onnx.
///
/// Maintains a persistent online recognizer and stream. Audio samples are fed
/// incrementally via ``feedSamples(_:)`` and partial results are available
/// immediately via ``getPartialResult()``.
///
/// Thread-safe: ``feedSamples(_:)`` and ``getPartialResult()`` can be called
/// from different threads (e.g. audio tap callback + main thread).
public final class SherpaLiveTranscriber: LiveTranscriber, @unchecked Sendable {

    private let modelPath: URL
    private var recognizer: OpaquePointer?
    private var stream: OpaquePointer?
    private var lastText = ""
    private let lock = NSLock()

    public init(modelPath: URL) {
        self.modelPath = modelPath
    }

    deinit {
        lock.lock()
        if let s = stream { SherpaOnnxDestroyOnlineStream(s) }
        if let r = recognizer { SherpaOnnxDestroyOnlineRecognizer(r) }
        lock.unlock()
    }

    // MARK: - LiveTranscriber

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        // Clean up any existing session
        if let s = stream { SherpaOnnxDestroyOnlineStream(s) }
        if let r = recognizer { SherpaOnnxDestroyOnlineRecognizer(r) }
        stream = nil
        recognizer = nil
        lastText = ""

        var config = try buildRecognizerConfig(modelDir: modelPath.path)
        guard let r = SherpaOnnxCreateOnlineRecognizer(&config) else {
            throw SherpaError.recognizerInitFailed
        }
        guard let s = SherpaOnnxCreateOnlineStream(r) else {
            SherpaOnnxDestroyOnlineRecognizer(r)
            throw SherpaError.streamInitFailed
        }
        recognizer = r
        stream = s
    }

    public func feedSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let s = stream, let r = recognizer else { return }

        SherpaOnnxOnlineStreamAcceptWaveform(s, 16000, samples, Int32(samples.count))

        while SherpaOnnxIsOnlineStreamReady(r, s) != 0 {
            SherpaOnnxDecodeOnlineStream(r, s)
        }
    }

    public func getPartialResult() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let s = stream, let r = recognizer else { return lastText }

        guard let resultPtr = SherpaOnnxGetOnlineStreamResult(r, s) else {
            return lastText
        }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(resultPtr) }

        if let cstr = resultPtr.pointee.text {
            lastText = String(cString: cstr)
        }
        return lastText
    }

    public func stop() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let s = stream, let r = recognizer else { return lastText }

        SherpaOnnxOnlineStreamInputFinished(s)
        while SherpaOnnxIsOnlineStreamReady(r, s) != 0 {
            SherpaOnnxDecodeOnlineStream(r, s)
        }

        if let resultPtr = SherpaOnnxGetOnlineStreamResult(r, s) {
            if let cstr = resultPtr.pointee.text {
                lastText = String(cString: cstr)
            }
            SherpaOnnxDestroyOnlineRecognizerResult(resultPtr)
        }

        SherpaOnnxDestroyOnlineStream(s)
        SherpaOnnxDestroyOnlineRecognizer(r)
        stream = nil
        recognizer = nil

        return lastText
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        guard let r = recognizer, let s = stream else { return }
        SherpaOnnxOnlineStreamReset(r, s)
        lastText = ""
    }

    // MARK: - Config

    private func buildRecognizerConfig(
        modelDir: String
    ) throws -> SherpaOnnxOnlineRecognizerConfig {
        let fm = FileManager.default

        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        guard fm.fileExists(atPath: tokensPath) else {
            throw SherpaError.missingFile("tokens.txt in \(modelDir)")
        }

        let contents = (try? fm.contentsOfDirectory(atPath: modelDir)) ?? []
        let onnxFiles = contents.filter { $0.hasSuffix(".onnx") }

        let hasEncoder = onnxFiles.contains { $0.contains("encoder") }
        let hasDecoder = onnxFiles.contains { $0.contains("decoder") }
        let hasJoiner = onnxFiles.contains { $0.contains("joiner") }

        let featConfig = SherpaOnnxFeatureConfig(sample_rate: 16000, feature_dim: 80)
        let nThreads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))

        guard hasEncoder && hasDecoder && hasJoiner else {
            throw SherpaError.unsupportedModelLayout(
                "Could not determine model type from files: \(onnxFiles.joined(separator: ", "))"
            )
        }

        let encoder = onnxFiles.first { $0.contains("encoder") } ?? ""
        let decoder = onnxFiles.first { $0.contains("decoder") } ?? ""
        let joiner = onnxFiles.first { $0.contains("joiner") } ?? ""

        let transducer = SherpaOnnxOnlineTransducerModelConfig(
            encoder: strdup((modelDir as NSString).appendingPathComponent(encoder)),
            decoder: strdup((modelDir as NSString).appendingPathComponent(decoder)),
            joiner: strdup((modelDir as NSString).appendingPathComponent(joiner))
        )

        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokensPath,
            transducer: transducer,
            numThreads: Int(nThreads)
        )

        return sherpaOnnxOnlineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            enableEndpoint: true,
            rule1MinTrailingSilence: 2.4,
            rule2MinTrailingSilence: 1.2,
            rule3MinUtteranceLength: 30
        )
    }
}
#endif

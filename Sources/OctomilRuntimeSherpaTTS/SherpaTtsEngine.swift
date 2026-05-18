#if canImport(sherpa_onnx)
import Foundation
import Octomil
import sherpa_onnx

/// Result of a sherpa-onnx on-device TTS synthesis.
public struct SherpaTtsSynthesisResult: Sendable {
    public let audioData: Data       // 16-bit PCM little-endian WAV
    public let contentType: String   // "audio/wav"
    public let format: String        // "wav"
    public let sampleRate: Int
    public let durationMs: Int
    public let voice: String?
    public let model: String

    public init(
        audioData: Data,
        contentType: String,
        format: String,
        sampleRate: Int,
        durationMs: Int,
        voice: String?,
        model: String
    ) {
        self.audioData = audioData
        self.contentType = contentType
        self.format = format
        self.sampleRate = sampleRate
        self.durationMs = durationMs
        self.voice = voice
        self.model = model
    }
}

public enum SherpaTtsEngineError: Error, LocalizedError {
    case modelNotFound(URL)
    case unsupportedModelFamily(String)
    case loadFailed(String)
    case synthesizeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let url):
            return "Sherpa TTS model not found at \(url.path)."
        case .unsupportedModelFamily(let name):
            return "Unsupported sherpa-onnx TTS model family: \(name)."
        case .loadFailed(let msg):
            return "Failed to load sherpa-onnx TTS model: \(msg)."
        case .synthesizeFailed(let msg):
            return "Sherpa TTS synthesis failed: \(msg)."
        }
    }
}

/// On-device text-to-speech engine backed by sherpa-onnx.
///
/// Mirrors the shape of ``SherpaStreamingEngine`` (ASR) so the optional
/// runtime targets stay symmetric. Caller is responsible for staging
/// the model directory (model.onnx + tokens + voices.bin or VITS files
/// + espeak-ng-data) at ``modelPath``.
public final class SherpaTtsEngine: @unchecked Sendable {
    private let modelPath: URL
    private let modelName: String
    private let family: SherpaTtsFamily
    private var tts: OpaquePointer?

    public init(modelPath: URL, modelName: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw SherpaTtsEngineError.modelNotFound(modelPath)
        }
        self.modelPath = modelPath
        let resolvedName = modelName ?? modelPath.lastPathComponent
        self.modelName = resolvedName
        guard let family = SherpaTtsFamily(modelName: resolvedName) else {
            throw SherpaTtsEngineError.unsupportedModelFamily(resolvedName)
        }
        self.family = family
        self.tts = try SherpaTtsEngine.makeTts(family: family, modelPath: modelPath)
    }

    deinit {
        if let tts {
            SherpaOnnxDestroyOfflineTts(tts)
        }
    }

    /// Synthesize speech from text. Returns a 16-bit PCM mono WAV plus
    /// metadata. ``voice`` defaults to the model's first speaker; ``speed``
    /// is a multiplier (1.0 default).
    public func synthesize(
        text: String,
        voice: String? = nil,
        speed: Float = 1.0
    ) throws -> SherpaTtsSynthesisResult {
        guard let tts else {
            throw SherpaTtsEngineError.loadFailed("TTS handle is nil")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SherpaTtsEngineError.synthesizeFailed("input must not be empty")
        }

        let sid = family.speakerId(for: voice)
        guard let audio = SherpaOnnxOfflineTtsGenerate(tts, text, Int32(sid), speed) else {
            throw SherpaTtsEngineError.synthesizeFailed("native generate returned null")
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let sampleRate = Int(audio.pointee.sample_rate)
        let n = Int(audio.pointee.n)
        // sherpa_onnx C ABI now declares `samples` as nullable
        // (`const float *` returned via Swift as `UnsafePointer<Float>?`).
        // Treat null as zero-length output rather than crashing.
        guard let samplesPtr = audio.pointee.samples else {
            throw SherpaTtsEngineError.synthesizeFailed("native generate returned null samples")
        }
        let wav = Self.samplesToWav(samples: samplesPtr, count: n, sampleRate: sampleRate)
        let durationMs = sampleRate > 0 ? (1000 * n / sampleRate) : 0

        return SherpaTtsSynthesisResult(
            audioData: wav,
            contentType: "audio/wav",
            format: "wav",
            sampleRate: sampleRate,
            durationMs: durationMs,
            voice: voice,
            model: modelName
        )
    }

    // MARK: - Loading

    private static func makeTts(
        family: SherpaTtsFamily,
        modelPath: URL
    ) throws -> OpaquePointer {
        let modelOnnx = modelPath.appendingPathComponent("model.onnx").path
        let tokens = modelPath.appendingPathComponent("tokens.txt").path
        let dataDir = modelPath.appendingPathComponent("espeak-ng-data").path

        var modelConfig = SherpaOnnxOfflineTtsModelConfig()
        modelConfig.num_threads = 2
        // sherpa_onnx C ABI: `provider` is `const char *` → Swift wants
        // `UnsafePointer<CChar>?`. `strdup` returns `UnsafeMutablePointer<CChar>?`;
        // re-cast to immutable. Allocation lifetime matches the OpaquePointer
        // owned by the engine; freed indirectly when the TTS handle is destroyed.
        modelConfig.provider = UnsafePointer(strdup("cpu"))

        switch family {
        case .kokoro:
            let voices = modelPath.appendingPathComponent("voices.bin").path
            // sherpa_onnx struct fields (in declaration order):
            //   model, voices, tokens, data_dir,
            //   length_scale (default 1.0), dict_dir (unused), lexicon, lang
            modelConfig.kokoro = SherpaOnnxOfflineTtsKokoroModelConfig(
                model: strdup(modelOnnx),
                voices: strdup(voices),
                tokens: strdup(tokens),
                data_dir: strdup(dataDir),
                length_scale: 1.0,
                dict_dir: nil,
                lexicon: nil,
                lang: nil
            )
        case .vits:
            // sherpa_onnx struct fields (in declaration order):
            //   model, lexicon, tokens, data_dir,
            //   noise_scale, noise_scale_w, length_scale, dict_dir (unused)
            // VITS defaults are the canonical values from the upstream model
            // configs: noise_scale=0.667, noise_scale_w=0.8, length_scale=1.0.
            modelConfig.vits = SherpaOnnxOfflineTtsVitsModelConfig(
                model: strdup(modelOnnx),
                lexicon: nil,
                tokens: strdup(tokens),
                data_dir: strdup(dataDir),
                noise_scale: 0.667,
                noise_scale_w: 0.8,
                length_scale: 1.0,
                dict_dir: nil
            )
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = modelConfig

        guard let handle = SherpaOnnxCreateOfflineTts(&config) else {
            throw SherpaTtsEngineError.loadFailed("CreateOfflineTts returned null")
        }
        return handle
    }

    private static func samplesToWav(
        samples: UnsafePointer<Float>,
        count: Int,
        sampleRate: Int
    ) -> Data {
        let bytesPerSample = 2
        let dataSize = count * bytesPerSample
        var pcm = Data(capacity: dataSize)
        for i in 0..<count {
            let clipped = max(-1.0, min(1.0, samples[i]))
            let s = Int16(clipped * 32767.0)
            withUnsafeBytes(of: s.littleEndian) { pcm.append(contentsOf: $0) }
        }
        return wavWrap(pcm: pcm, sampleRate: sampleRate)
    }

    private static func wavWrap(pcm: Data, sampleRate: Int) -> Data {
        var header = Data()
        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize
        let byteRate = UInt32(sampleRate * 2)
        let blockAlign: UInt16 = 2

        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian, Array.init))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))   // PCM
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))   // mono
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian, Array.init))  // bits/sample
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        header.append(pcm)
        return header
    }
}
#endif

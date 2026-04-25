#if canImport(sherpa_onnx)
import Foundation

/// sherpa-onnx TTS model family. Selects which OfflineTtsModelConfig
/// variant to load and which voice catalog to consult.
enum SherpaTtsFamily {
    case kokoro
    case vits

    init?(modelName: String) {
        let lower = modelName.lowercased()
        if lower.hasPrefix("kokoro-") {
            self = .kokoro
        } else if lower.hasPrefix("piper-") || lower.hasPrefix("vits-") {
            self = .vits
        } else {
            return nil
        }
    }

    /// Map a voice name to a sherpa-onnx speaker id. Falls back to sid 0
    /// (the model's first/default speaker) when voice is nil/unknown.
    func speakerId(for voice: String?) -> Int {
        guard let voice, !voice.isEmpty else { return 0 }
        switch self {
        case .kokoro:
            return SherpaTtsFamily.kokoroVoices.firstIndex(of: voice.lowercased()) ?? 0
        case .vits:
            // Single-speaker by default; multi-speaker bundles ship a
            // voices.txt the client can consult before calling synthesize().
            return 0
        }
    }

    /// Kokoro v0.19+ voice catalog. Index == speaker id in the bundled
    /// voices.bin. Mirrors the Python `_KOKORO_VOICES` list so cross-SDK
    /// callers see consistent voice ids. Operators with a custom Kokoro
    /// build can override this by passing an explicit voice argument
    /// after looking up the sid in their bundle.
    static let kokoroVoices: [String] = [
        "af_alloy",
        "af_aoede",
        "af_bella",
        "af_heart",
        "af_jessica",
        "af_kore",
        "af_nicole",
        "af_nova",
        "af_river",
        "af_sarah",
        "af_sky",
        "am_adam",
        "am_echo",
        "am_eric",
        "am_fenrir",
        "am_liam",
        "am_michael",
        "am_onyx",
        "am_puck",
        "am_santa",
        "bf_alice",
        "bf_emma",
        "bf_isabella",
        "bf_lily",
        "bm_daniel",
        "bm_fable",
        "bm_george",
        "bm_lewis",
    ]
}
#endif

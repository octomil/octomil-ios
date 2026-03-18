import sherpa_onnx

/// Empty string pointer for sherpa-onnx config fields.
/// sherpa-onnx crashes with SIGSEGV on NULL string pointers (calls strlen
/// without NULL checks), so every `const char *` field must be a valid pointer.
private let empty = UnsafePointer(strdup(""))!

/// Convenience initializer for SherpaOnnxOnlineModelConfig.
///
/// All `const char *` fields are initialized to empty strings to prevent
/// NULL-pointer crashes in the sherpa-onnx C++ code.
func sherpaOnnxOnlineModelConfig(
    tokens: String,
    transducer: SherpaOnnxOnlineTransducerModelConfig,
    numThreads: Int
) -> SherpaOnnxOnlineModelConfig {
    return SherpaOnnxOnlineModelConfig(
        transducer: transducer,
        paraformer: SherpaOnnxOnlineParaformerModelConfig(encoder: empty, decoder: empty),
        zipformer2_ctc: SherpaOnnxOnlineZipformer2CtcModelConfig(model: empty),
        tokens: UnsafePointer(strdup(tokens)),
        num_threads: Int32(numThreads),
        provider: UnsafePointer(strdup("cpu")),
        debug: 1,
        model_type: UnsafePointer(strdup("zipformer2")),
        modeling_unit: empty,
        bpe_vocab: empty,
        tokens_buf: empty,
        tokens_buf_size: 0,
        nemo_ctc: SherpaOnnxOnlineNemoCtcModelConfig(model: empty),
        t_one_ctc: SherpaOnnxOnlineToneCtcModelConfig(model: empty)
    )
}

/// Convenience initializer for SherpaOnnxOnlineRecognizerConfig.
///
/// All `const char *` fields are initialized to empty strings to prevent
/// NULL-pointer crashes in the sherpa-onnx C++ code.
func sherpaOnnxOnlineRecognizerConfig(
    featConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOnlineModelConfig,
    enableEndpoint: Bool,
    rule1MinTrailingSilence: Float,
    rule2MinTrailingSilence: Float,
    rule3MinUtteranceLength: Float
) -> SherpaOnnxOnlineRecognizerConfig {
    return SherpaOnnxOnlineRecognizerConfig(
        feat_config: featConfig,
        model_config: modelConfig,
        decoding_method: UnsafePointer(strdup("greedy_search")),
        max_active_paths: 4,
        enable_endpoint: enableEndpoint ? 1 : 0,
        rule1_min_trailing_silence: rule1MinTrailingSilence,
        rule2_min_trailing_silence: rule2MinTrailingSilence,
        rule3_min_utterance_length: rule3MinUtteranceLength,
        hotwords_file: empty,
        hotwords_score: 0,
        ctc_fst_decoder_config: SherpaOnnxOnlineCtcFstDecoderConfig(graph: empty, max_active: 0),
        rule_fsts: empty,
        rule_fars: empty,
        blank_penalty: 0.0
    )
}

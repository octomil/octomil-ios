import sherpa_onnx

/// Convenience initializer for SherpaOnnxOnlineModelConfig.
///
/// Creates a config with the transducer model, tokens path, and thread count,
/// zeroing out all other fields.
func sherpaOnnxOnlineModelConfig(
    tokens: String,
    transducer: SherpaOnnxOnlineTransducerModelConfig,
    numThreads: Int
) -> SherpaOnnxOnlineModelConfig {
    var config = SherpaOnnxOnlineModelConfig()
    config.transducer = transducer
    config.tokens = UnsafePointer(strdup(tokens))
    config.num_threads = Int32(numThreads)
    config.provider = UnsafePointer(strdup("cpu"))
    config.model_type = UnsafePointer(strdup("zipformer2"))
    config.debug = 1
    return config
}

/// Convenience initializer for SherpaOnnxOnlineRecognizerConfig.
///
/// Creates a config with feature config, model config, and endpoint settings,
/// zeroing out all other fields.
func sherpaOnnxOnlineRecognizerConfig(
    featConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOnlineModelConfig,
    enableEndpoint: Bool,
    rule1MinTrailingSilence: Float,
    rule2MinTrailingSilence: Float,
    rule3MinUtteranceLength: Float
) -> SherpaOnnxOnlineRecognizerConfig {
    var config = SherpaOnnxOnlineRecognizerConfig()
    config.feat_config = featConfig
    config.model_config = modelConfig
    config.decoding_method = UnsafePointer(strdup("greedy_search"))
    config.max_active_paths = 4
    config.enable_endpoint = enableEndpoint ? 1 : 0
    config.rule1_min_trailing_silence = rule1MinTrailingSilence
    config.rule2_min_trailing_silence = rule2MinTrailingSilence
    config.rule3_min_utterance_length = rule3MinUtteranceLength
    return config
}

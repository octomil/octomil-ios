// Auto-generated span event name constants.

public enum SpanEventName {
    public static let firstToken = "first_token"
    public static let chunkProduced = "chunk_produced"
    public static let toolCallEmitted = "tool_call_emitted"
    public static let fallbackTriggered = "fallback_triggered"
    public static let completed = "completed"
    public static let toolCallParseSucceeded = "tool_call_parse_succeeded"
    public static let toolCallParseFailed = "tool_call_parse_failed"
    public static let kvCacheApplied = "kv_cache_applied"
    public static let credentialResolved = "credential_resolved"
    public static let downloadStarted = "download_started"
    public static let downloadCompleted = "download_completed"
    public static let checksumVerified = "checksum_verified"
    public static let runtimeInitialized = "runtime_initialized"
    public static let chunkDownloadStarted = "chunk_download_started"
    public static let chunkDownloadCompleted = "chunk_download_completed"
    public static let chunkDownloadFailed = "chunk_download_failed"
    public static let artifactVerified = "artifact_verified"
    public static let warmingStarted = "warming_started"
    public static let healthcheckPassed = "healthcheck_passed"
    public static let healthcheckFailed = "healthcheck_failed"
    public static let activationComplete = "activation_complete"
    public static let rollbackTriggered = "rollback_triggered"
    public static let planFetched = "plan_fetched"
    public static let localTrainingStarted = "local_training_started"
    public static let localTrainingCompleted = "local_training_completed"
    public static let updateClipped = "update_clipped"
    public static let updateNoised = "update_noised"
    public static let updateEncrypted = "update_encrypted"
    public static let uploadStarted = "upload_started"
    public static let uploadCompleted = "upload_completed"
    public static let participationAborted = "participation_aborted"
    public static let roundStarted = "round_started"
    public static let roundAggregated = "round_aggregated"
    public static let candidatePublished = "candidate_published"
    public static let jobCompleted = "job_completed"
    public static let desiredStateFetched = "desired_state_fetched"
    public static let observedStateReported = "observed_state_reported"
    public static let stateDriftDetected = "state_drift_detected"
    public static let deviceRegistered = "device.registered"

    public static let eventParentSpan: [String: String] = [
        "first_token": "octomil.response",
        "chunk_produced": "octomil.response",
        "tool_call_emitted": "octomil.response",
        "fallback_triggered": "octomil.response",
        "completed": "octomil.response",
        "tool_call_parse_succeeded": "octomil.response",
        "tool_call_parse_failed": "octomil.response",
        "kv_cache_applied": "octomil.response",
        "credential_resolved": "octomil.fallback.cloud",
        "download_started": "octomil.model.load",
        "download_completed": "octomil.model.load",
        "checksum_verified": "octomil.model.load",
        "runtime_initialized": "octomil.model.load",
        "chunk_download_started": "octomil.artifact.download",
        "chunk_download_completed": "octomil.artifact.download",
        "chunk_download_failed": "octomil.artifact.download",
        "artifact_verified": "octomil.artifact.download",
        "warming_started": "octomil.artifact.activation",
        "healthcheck_passed": "octomil.artifact.activation",
        "healthcheck_failed": "octomil.artifact.activation",
        "activation_complete": "octomil.artifact.activation",
        "rollback_triggered": "octomil.artifact.activation",
        "plan_fetched": "octomil.federation.round",
        "local_training_started": "octomil.federation.round",
        "local_training_completed": "octomil.federation.round",
        "update_clipped": "octomil.federation.round",
        "update_noised": "octomil.federation.round",
        "update_encrypted": "octomil.federation.round",
        "upload_started": "octomil.federation.round",
        "upload_completed": "octomil.federation.round",
        "participation_aborted": "octomil.federation.round",
        "round_started": "octomil.training.job",
        "round_aggregated": "octomil.training.job",
        "candidate_published": "octomil.training.job",
        "job_completed": "octomil.training.job",
        "desired_state_fetched": "octomil.device.sync",
        "observed_state_reported": "octomil.device.sync",
        "state_drift_detected": "octomil.device.sync",
        "device.registered": "octomil.control.register",
    ]
}

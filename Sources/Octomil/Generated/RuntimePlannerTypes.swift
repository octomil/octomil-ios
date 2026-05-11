// Auto-generated from octomil-contracts runtime_planner schemas. Do not edit.

public struct RuntimePlannerJSONValue: Codable, Sendable {
    public init() {}
    public init(from decoder: Decoder) throws {}
    public func encode(to encoder: Encoder) throws {}
}

public struct AppResolution: Codable, Sendable {
    public let app_id: String
    public let app_slug: String?
    public let capability: String
    public let routing_policy: String
    public let selected_model: String
    public let selected_model_variant_id: String?
    public let selected_model_version: String?
    public let artifact_candidates: [RuntimeArtifactPlan]?
    public let preferred_engines: [String]?
    public let fallback_policy: String?
    public let plan_ttl_seconds: Int?
    public let public_client_allowed: Bool?
}

public struct CandidateGate: Codable, Sendable {
    public let code: String
    public let required: Bool
    public let threshold_number: Double?
    public let threshold_string: String?
    public let window_seconds: Int?
    public let source: String
    public let gate_class: String
    public let evaluation_phase: String
    public let fallback_eligible: Bool
    public let blocking_default: Bool?
}

public struct DeviceRuntimeProfile: Codable, Sendable {
    public let sdk: String
    public let sdk_version: String
    public let platform: String
    public let arch: String
    public let os_version: String?
    public let chip: String?
    public let ram_total_bytes: Int?
    public let gpu_core_count: Int?
    public let accelerators: [String]?
    public let installed_runtimes: [InstalledRuntime]?
    public let supported_gate_codes: [String]?
}

public struct InstalledRuntime: Codable, Sendable {
    public let engine: String
    public let version: String?
    public let available: Bool?
    public let accelerator: String?
    public let metadata: [String: RuntimePlannerJSONValue]?
}

public struct RouteAttempt: Codable, Sendable {
    public let index: Int
    public let locality: String
    public let mode: String
    public let engine: String?
    public let artifact: AttemptArtifact?
    public let status: String
    public let stage: String
    public let gate_results: [GateResult]?
    public let reason: [String: RuntimePlannerJSONValue]
}

public struct AttemptArtifact: Codable, Sendable {
    public let id: String?
    public let digest: String?
    public let cache: [String: RuntimePlannerJSONValue]?
}

public struct GateResult: Codable, Sendable {
    public let code: String
    public let status: String
    public let observed_number: Double?
    public let threshold_number: Double?
    public let threshold_string: String?
    public let reason_code: String?
    public let gate_class: String
    public let evaluation_phase: String
    public let required: Bool?
    public let fallback_eligible: Bool?
    public let observed_string: String?
    public let safe_metadata: [String: RuntimePlannerJSONValue]?
}

public struct RouteEvent: Codable, Sendable {
    public let route_id: String
    public let request_id: String
    public let plan_id: String?
    public let app_id: String?
    public let app_slug: String?
    public let deployment_id: String?
    public let experiment_id: String?
    public let variant_id: String?
    public let capability: String?
    public let policy: String?
    public let planner_source: String?
    public let model_ref: String?
    public let model_ref_kind: ContractModelRefKind?
    public let selected_locality: String?
    public let final_locality: String?
    public let final_mode: String?
    public let engine: String?
    public let artifact_id: String?
    public let cache_status: String?
    public let fallback_used: Bool
    public let fallback_trigger_code: String?
    public let fallback_trigger_stage: String?
    public let candidate_attempts: Int
    public let attempt_details: [RouteEventAttemptDetail]?
    public let ttft_ms: Double?
    public let tokens_per_second: Double?
    public let total_tokens: Int?
    public let duration_ms: Double?
}

public struct RouteEventAttemptDetail: Codable, Sendable {
    public let index: Int
    public let locality: String
    public let mode: String
    public let engine: String?
    public let status: String
    public let stage: String
    public let gate_summary: [String: RuntimePlannerJSONValue]
    public let reason_code: String
}

public struct RouteMetadata: Codable, Sendable {
    public let status: String
    public let execution: RouteExecution?
    public let model: RouteModel
    public let artifact: RouteArtifact?
    public let planner: PlannerInfo
    public let fallback: FallbackInfo
    public let attempts: [RouteAttempt]?
    public let reason: RouteReason
}

public struct RouteExecution: Codable, Sendable {
    public let locality: String
    public let mode: String
    public let engine: String?
}

public struct RouteModel: Codable, Sendable {
    public let requested: RouteModelRequested
    public let resolved: RouteModelResolved?
}

public struct RouteModelRequested: Codable, Sendable {
    public let ref: String
    public let kind: ContractModelRefKind
    public let capability: String?
}

public struct RouteModelResolved: Codable, Sendable {
    public let id: String?
    public let slug: String?
    public let version_id: String?
    public let variant_id: String?
}

public struct RouteArtifact: Codable, Sendable {
    public let id: String?
    public let version: String?
    public let format: String?
    public let digest: String?
    public let cache: ArtifactCache?
}

public struct ArtifactCache: Codable, Sendable {
    public let status: String
    public let managed_by: String?
}

public struct PlannerInfo: Codable, Sendable {
    public let source: String
}

public struct FallbackInfo: Codable, Sendable {
    public let used: Bool
    public let from_attempt: Int?
    public let to_attempt: Int?
    public let trigger: FallbackTrigger?
}

public struct FallbackTrigger: Codable, Sendable {
    public let code: String
    public let stage: String
    public let message: String
    public let gate_code: String?
    public let gate_class: String?
    public let evaluation_phase: String?
    public let candidate_index: Int?
    public let output_visible_before_failure: Bool?
}

public struct RouteReason: Codable, Sendable {
    public let code: String
    public let message: String
}

public struct RuntimeBenchmarkSubmission: Codable, Sendable {
    public let source: String?
    public let model: String
    public let model_version: String?
    public let artifact_digest: String?
    public let capability: String
    public let engine: String
    public let engine_version: String?
    public let quantization: String?
    public let device: DeviceRuntimeProfile
    public let benchmark_tokens: Int?
    public let ttft_ms: Double?
    public let tokens_per_second: Double?
    public let latency_ms: Double?
    public let peak_memory_bytes: Int?
    public let success: Bool
    public let error_code: String?
    public let metadata: [String: RuntimePlannerJSONValue]?
}

public struct RuntimeBenchmarkSubmissionResponse: Codable, Sendable {
    public let id: String
    public let accepted: Bool
    public let created_at: String
}

public struct RuntimeDefaultsResponse: Codable, Sendable {
    public let default_engines: [String: RuntimePlannerJSONValue]
    public let supported_capabilities: [String]
    public let supported_policies: [String]
    public let plan_ttl_seconds: Int
}

public struct RuntimePlanRequest: Codable, Sendable {
    public let model: String
    public let capability: String
    public let routing_policy: String?
    public let app_id: String?
    public let app_slug: String?
    public let org_id: String?
    public let device: DeviceRuntimeProfile
    public let allow_cloud_fallback: Bool?
}

public struct RuntimePlanResponse: Codable, Sendable {
    public let plan_schema_version: Int?
    public let model: String
    public let capability: String
    public let policy: String
    public let candidates: [RuntimeCandidatePlan]
    public let fallback_candidates: [RuntimeCandidatePlan]?
    public let plan_ttl_seconds: Int?
    public let fallback_allowed: Bool?
    public let public_client_allowed: Bool?
    public let server_generated_at: String
    public let plan_correlation_id: String?
    public let app_resolution: AppResolution?
    public let resolution: ModelResolution?
}

public struct ModelResolution: Codable, Sendable {
    public let ref_kind: ContractModelRefKind
    public let original_ref: String
    public let resolved_model: String
    public let deployment_id: String?
    public let deployment_key: String?
    public let experiment_id: String?
    public let variant_id: String?
    public let variant_name: String?
    public let capability: String?
    public let routing_policy: String?
}

public struct RuntimeCandidatePlan: Codable, Sendable {
    public let locality: String
    public let engine: String?
    public let engine_version_constraint: String?
    public let artifact: RuntimeArtifactPlan?
    public let priority: Int
    public let confidence: Double
    public let reason: String
    public let benchmark_required: Bool?
    public let gates: [CandidateGate]?
    public let delivery_mode: String?
    public let prepare_required: Bool?
    public let prepare_policy: String?
}

public struct RuntimeArtifactPlan: Codable, Sendable {
    public let model_id: String
    public let artifact_id: String?
    public let model_version: String?
    public let format: String?
    public let quantization: String?
    public let uri: String?
    public let digest: String?
    public let size_bytes: Int?
    public let min_ram_bytes: Int?
    public let required_files: [String]?
    public let download_urls: [[String: RuntimePlannerJSONValue]]?
    public let manifest_uri: String?
}

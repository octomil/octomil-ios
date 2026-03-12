// Auto-generated from octomil-contracts. Do not edit.
//
// Renamed from TelemetryEvent to ContractTelemetryEventName
// to avoid collision with the existing TelemetryEvent struct
// in Telemetry/TelemetryV2Models.swift.

/// Canonical telemetry event name constants from the contract.
public enum ContractTelemetryEventName {
    public static let inferenceStarted = "inference.started"
    public static let inferenceCompleted = "inference.completed"
    public static let inferenceFailed = "inference.failed"
    public static let inferenceChunkProduced = "inference.chunk_produced"
    public static let deployStarted = "deploy.started"
    public static let deployCompleted = "deploy.completed"
}

// Auto-generated from octomil-contracts. Do not edit.

public enum DeviceModelStatus: String, Codable, Sendable {
    case notAssigned = "not_assigned"
    case assigned = "assigned"
    case downloading = "downloading"
    case downloadFailed = "download_failed"
    case verifying = "verifying"
    case ready = "ready"
    case loading = "loading"
    case loadFailed = "load_failed"
    case active = "active"
    case fallbackActive = "fallback_active"
    case deprecatedAssigned = "deprecated_assigned"
}

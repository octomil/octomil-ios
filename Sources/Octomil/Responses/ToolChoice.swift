import Foundation

/// Controls how the model selects tools.
public enum ToolChoice: Sendable {
    case auto
    case none
    case required
    case specific(String)
}

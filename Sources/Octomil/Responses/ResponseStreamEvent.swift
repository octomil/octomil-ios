import Foundation

/// Events emitted during a streaming response.
public enum ResponseStreamEvent: Sendable {
    case textDelta(String)
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsDelta: String?)
    case done(Response)
    case error(Error)
}

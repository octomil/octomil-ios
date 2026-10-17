import Foundation

/// Process-wide pin registry so clients that build their own URLSession still honor
/// `OctomilConfiguration.pinnedCertificateHashes` for the API host.
enum PinnedSession {

    private struct State {
        var hashes: [String] = []
        var hosts: Set<String> = []
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var state = State()

        func update(_ body: (inout State) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            body(&state)
        }

        func snapshot() -> State {
            lock.lock()
            defer { lock.unlock() }
            return state
        }
    }

    private static let store = Store()

    static func register(hashes: [String], host: String?) {
        guard !hashes.isEmpty, let host else { return }
        store.update {
            $0.hashes = hashes
            $0.hosts.insert(host.lowercased())
        }
    }

    /// Shared session for ad-hoc requests that previously used `URLSession.shared`.
    static let shared = make(configuration: .default)

    static func make(configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration, delegate: Delegate(), delegateQueue: nil)
    }

    private final class Delegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            let snapshot = PinnedSession.store.snapshot()

            let host = challenge.protectionSpace.host.lowercased()
            guard snapshot.hosts.contains(host) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            CertificatePinningDelegate(pinnedHashes: snapshot.hashes, pinnedHost: host)
                .urlSession(session, didReceive: challenge, completionHandler: completionHandler)
        }
    }
}

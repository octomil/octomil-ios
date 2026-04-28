// Cross-process file lock for artifact downloads.
//
// Port of Python ``octomil/runtime/lifecycle/file_lock.py`` and the
// Node ``src/prepare/file-lock.ts``. Prevents concurrent downloads of
// the same artifact across processes (multiple iOS app extensions,
// host process + helper, etc.).
//
// Apple platforms have ``flock(2)`` available via ``Darwin``, but
// using it cleanly across process exits is finicky — a crashed
// holder leaves the file behind, and the kernel-level advisory lock
// is released only when the file descriptor is closed (which doesn't
// always happen if the process dies abnormally). We use the same
// fallback-style approach as the Node port: ``open(O_CREAT|O_EXCL)``
// for atomic creation, plus a heartbeat mtime refresh and stale-lock
// stealing for crashed holders. The contract matches the other
// SDKs: ``acquire(timeout:)`` blocks up to ``timeout`` seconds;
// ``release()`` removes the file; ``Task.detach`` runs the heartbeat.
//
// The lock filename comes from ``safeFilesystemKey`` so PrepareManager
// (artifact dir) and FileLock (lock file) use the same key shape.

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import Foundation

public enum FileLockError: Error, CustomStringConvertible {
    case timeout(path: URL, timeoutSeconds: TimeInterval)

    public var description: String {
        switch self {
        case let .timeout(path, timeout):
            return "Could not acquire lock \(path.path) within \(timeout)s. Another process may be downloading this artifact."
        }
    }
}

/// Cross-process file lock backed by ``open(O_CREAT|O_EXCL)``.
public actor FileLock {
    public let lockURL: URL
    private let timeoutSeconds: TimeInterval
    private let pollIntervalSeconds: TimeInterval
    private let staleTimeoutSeconds: TimeInterval
    private var fd: Int32 = -1
    private var heartbeat: Task<Void, Never>?

    public init(
        name: String,
        lockDir: URL? = nil,
        timeoutSeconds: TimeInterval = 300,
        pollIntervalSeconds: TimeInterval = 0.5,
        staleTimeoutSeconds: TimeInterval = 5 * 60
    ) throws {
        let dir = lockDir ?? Self.defaultLockDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = try safeFilesystemKey(name)
        self.lockURL = dir.appendingPathComponent("\(safeName).lock")
        self.timeoutSeconds = timeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
        self.staleTimeoutSeconds = staleTimeoutSeconds
    }

    /// Where lock files land by default. Mirror of Python's
    /// ``_default_lock_dir`` — same priority order so the iOS host
    /// process and a Python sibling on macOS write to the same
    /// directory when sharing a cache root via ``OCTOMIL_CACHE_DIR``.
    public static func defaultLockDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let cacheRoot = env["OCTOMIL_CACHE_DIR"] {
            return URL(fileURLWithPath: cacheRoot)
                .appendingPathComponent("artifacts")
                .appendingPathComponent(".locks")
        }
        if let xdg = env["XDG_CACHE_HOME"] {
            return URL(fileURLWithPath: xdg)
                .appendingPathComponent("octomil")
                .appendingPathComponent("artifacts")
                .appendingPathComponent(".locks")
        }
        // ``homeDirectoryForCurrentUser`` is unavailable on iOS; on
        // mobile platforms the canonical cache root is the per-app
        // ``Library/Caches`` directory.
        #if os(iOS) || os(tvOS) || os(watchOS)
            if let caches = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
                return caches
                    .appendingPathComponent("octomil")
                    .appendingPathComponent("artifacts")
                    .appendingPathComponent(".locks")
            }
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("octomil")
                .appendingPathComponent("artifacts")
                .appendingPathComponent(".locks")
        #else
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home
                .appendingPathComponent(".cache")
                .appendingPathComponent("octomil")
                .appendingPathComponent("artifacts")
                .appendingPathComponent(".locks")
        #endif
    }

    public var isLocked: Bool { fd >= 0 }

    /// Acquire the lock, blocking up to ``timeoutSeconds``. Throws
    /// ``FileLockError.timeout`` on deadline.
    public func acquire() async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        while true {
            let path = lockURL.path
            let opened = path.withCString { ptr -> Int32 in
                Darwin.open(ptr, O_CREAT | O_EXCL | O_RDWR, 0o644)
            }
            if opened >= 0 {
                fd = opened
                startHeartbeat()
                return
            }
            // EEXIST is the expected "someone else has it" path.
            if errno != EEXIST {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            // Stale-lock check.
            if try await tryStealStaleLock() {
                continue
            }
            if Date() >= deadline {
                throw FileLockError.timeout(path: lockURL, timeoutSeconds: timeoutSeconds)
            }
            try await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
        }
    }

    /// Release the lock. Idempotent.
    public func release() async {
        heartbeat?.cancel()
        heartbeat = nil
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        try? FileManager.default.removeItem(at: lockURL)
    }

    deinit {
        // ``deinit`` cannot be ``async`` and cannot await on the
        // actor. If the caller forgot ``release()``, the heartbeat
        // task is cancelled (best effort) and the next holder will
        // detect the lock as stale.
        heartbeat?.cancel()
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    // MARK: - Internals

    /// Refresh the lock file's mtime every ``staleTimeoutSeconds /
    /// 5`` seconds so other waiters can distinguish "long download
    /// in progress" from "the holder process died". Without this, a
    /// 30-min download would be stolen at the 5-min stale cutoff.
    private func startHeartbeat() {
        let interval = max(staleTimeoutSeconds / 5, 1)
        let url = lockURL
        heartbeat = Task.detached(priority: .background) { [interval, url] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                let now = Date()
                try? FileManager.default.setAttributes(
                    [.modificationDate: now],
                    ofItemAtPath: url.path
                )
            }
        }
    }

    /// Returns ``true`` if a stale lock was found and removed (the
    /// caller should retry ``open(O_CREAT|O_EXCL)``).
    private func tryStealStaleLock() async throws -> Bool {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        } catch {
            // Disappeared between EEXIST and stat; the next iteration
            // will succeed at ``open(O_CREAT|O_EXCL)``.
            return true
        }
        guard let mtime = attrs[.modificationDate] as? Date else {
            return false
        }
        let age = Date().timeIntervalSince(mtime)
        if age <= staleTimeoutSeconds {
            return false
        }
        do {
            try FileManager.default.removeItem(at: lockURL)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            // Permission / FS error — let the next iteration time out.
            return false
        }
    }
}

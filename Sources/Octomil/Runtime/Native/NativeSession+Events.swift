import Foundation

extension NativeSession {
    /// Drains `pollEvent` into an `AsyncThrowingStream` that finishes
    /// on `.sessionCompleted` or thrown errors. Lets consumers use the
    /// `for try await event in session.events() { ... }` idiom instead
    /// of writing the polling loop by hand. Pattern-consistent with
    /// `ModelRuntime.stream(request:)` in `Runtime/Core/`.
    public func events(
        pollInterval: TimeInterval = 0.05
    ) -> AsyncThrowingStream<NativeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    while !Task.isCancelled {
                        guard let event = try await self.pollEvent(timeout: pollInterval) else {
                            if pollInterval == 0 {
                                await Task.yield()
                            }
                            continue
                        }
                        continuation.yield(event)
                        if case .sessionCompleted = event {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

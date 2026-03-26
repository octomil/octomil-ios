import Foundation

/// Device-oriented facade over ``ControlSync``.
///
/// Newer SDK surfaces prefer the `devices.*` namespace while the underlying
/// transport still lives in ``ControlSync``.
public final class DevicesClient: @unchecked Sendable {
    private let control: ControlSync
    private let deviceIdProvider: @Sendable () -> String?

    public init(
        control: ControlSync,
        deviceIdProvider: @escaping @Sendable () -> String?
    ) {
        self.control = control
        self.deviceIdProvider = deviceIdProvider
    }

    public func desiredState() async throws -> DesiredStateResponse {
        guard let deviceId = deviceIdProvider() else {
            throw OctomilError.deviceNotRegistered
        }
        return try await control.fetchDesiredState(deviceId: deviceId)
    }

    public func observedState(models: [ObservedModelEntry] = []) async throws {
        guard let deviceId = deviceIdProvider() else {
            throw OctomilError.deviceNotRegistered
        }
        try await control.reportObservedState(deviceId: deviceId, models: models)
    }

    public func sync(request: DeviceSyncRequest = DeviceSyncRequest()) async throws -> DeviceSyncResponse {
        guard let deviceId = deviceIdProvider() else {
            throw OctomilError.deviceNotRegistered
        }
        return try await control.sync(deviceId: deviceId, request: request)
    }
}

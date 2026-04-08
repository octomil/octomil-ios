import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Device Registration

extension OctomilClient {

    /// Registers this device with the Octomil server.
    ///
    /// Registration establishes this device's identity and enables
    /// participation in federated learning rounds.
    ///
    /// - Parameters:
    ///   - deviceId: Client-generated device ID (e.g., IDFV). If nil, auto-generated.
    ///   - appVersion: Host application version.
    ///   - metadata: Optional additional metadata.
    /// - Returns: Registration information including server-assigned ID.
    /// - Throws: `OctomilError` if registration fails.
    public func register(
        deviceId: String? = nil,
        appVersion: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> DeviceRegistrationResponse {
        emitState(.initializing)

        if configuration.enableLogging {
            logger.info("Registering device...")
        }

        // Generate or use provided device identifier.
        // Priority: register() parameter > constructor deviceId > auto-generated
        let identifier = deviceId ?? self.clientDeviceIdentifier ?? generateDeviceIdentifier()
        self.clientDeviceIdentifier = identifier

        let deviceInfo = await buildDeviceInfo()

        let capabilities = DeviceCapabilities(
            supportsTraining: deviceInfo.supportsTraining,
            coremlVersion: deviceInfo.coremlVersion,
            hasNeuralEngine: deviceInfo.hasNeuralEngine,
            maxBatchSize: 32,
            supportedFormats: ["coreml", "onnx"]
        )

        let hardwareInfo = DeviceInfoRequest(
            manufacturer: "Apple",
            model: deviceInfo.deviceModel,
            cpuArchitecture: DeviceMetadata().cpuArchitecture,
            gpuAvailable: deviceInfo.hasNeuralEngine,
            totalMemoryMb: deviceInfo.totalMemoryMb,
            availableStorageMb: deviceInfo.availableStorageMb
        )

        // Collect battery state for flat fields
        var batteryPct: Int? = nil
        var charging: Bool? = nil
        #if canImport(UIKit)
        let batteryState = await MainActor.run { () -> (level: Float, state: UIDevice.BatteryState) in
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            let state = UIDevice.current.batteryState
            return (level, state)
        }
        if batteryState.level >= 0 {
            batteryPct = Int(batteryState.level * 100)
        }
        charging = batteryState.state != .unplugged && batteryState.state != .unknown
        #endif

        let request = DeviceRegistrationRequest(
            deviceIdentifier: identifier,
            orgId: orgId,
            platform: "ios",
            osVersion: deviceInfo.osVersion,
            sdkVersion: OctomilVersion.current,
            appVersion: appVersion,
            deviceInfo: hardwareInfo,
            locale: deviceInfo.locale,
            region: deviceInfo.region,
            timezone: deviceInfo.timezone,
            metadata: metadata,
            capabilities: capabilities,
            manufacturer: "Apple",
            model: DeviceMetadata().model,
            cpuArchitecture: DeviceMetadata().cpuArchitecture,
            gpuAvailable: deviceInfo.hasNeuralEngine,
            totalMemoryMb: deviceInfo.totalMemoryMb,
            availableStorageMb: deviceInfo.availableStorageMb,
            batteryPct: batteryPct,
            charging: charging
        )

        let registration = try await apiClient.registerDevice(request)

        // Store registration info
        self.serverDeviceId = registration.id
        self.deviceRegistration = registration

        // Store server device ID securely for persistence
        try? secureStorage.storeServerDeviceId(registration.id)

        // Start automatic heartbeat
        startHeartbeat()

        emitState(.ready)

        if configuration.enableLogging {
            logger.info("Device registered with ID: \(registration.id)")
        }

        return registration
    }

    /// Registers this device with the Octomil server.
    ///
    /// - Note: Deprecated. Use ``register(deviceId:appVersion:metadata:)`` instead.
    @available(*, deprecated, renamed: "register(deviceId:appVersion:metadata:)")
    public func register(
        deviceIdentifier: String? = nil,
        appVersion: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> DeviceRegistrationResponse {
        try await register(deviceId: deviceIdentifier, appVersion: appVersion, metadata: metadata)
    }

    // MARK: - Silent Registration

    /// Performs device registration in the background without blocking the caller.
    ///
    /// On success, updates ``deviceContext`` with the server device ID and token.
    /// On failure, marks ``deviceContext`` as failed and schedules a retry.
    /// Registration failure never blocks local inference.
    internal func silentRegister() async {
        do {
            let registration = try await register(deviceId: nil)

            // Update DeviceContext with registration result
            if let context = deviceContext {
                // Use access token from the registration if available,
                // otherwise use the configured token
                let accessToken = (try? secureStorage.getDeviceToken()) ?? ""
                let expiresAt = Date().addingTimeInterval(3600) // 1 hour default
                await context.updateRegistered(
                    serverDeviceId: registration.id,
                    accessToken: accessToken,
                    expiresAt: expiresAt
                )
            }

            if configuration.enableLogging {
                logger.info("Silent registration succeeded: \(registration.id)")
            }

            // Set up artifact reconciler for auto-recovery and background sync
            await setupArtifactReconciler(deviceId: registration.id)
        } catch {
            if configuration.enableLogging {
                logger.warning("Silent registration failed: \(error.localizedDescription)")
            }
            await deviceContext?.markFailed(error)
            scheduleRegistrationRetry(attempt: 1)
        }
    }

    /// Schedules an exponential-backoff retry for silent registration.
    ///
    /// Delay: min(2^attempt + jitter, 300) seconds.
    internal func scheduleRegistrationRetry(attempt: Int) {
        let maxDelay: TimeInterval = 300 // 5 minutes
        let baseDelay = min(pow(2.0, Double(attempt)), maxDelay)
        let jitter = Double.random(in: 0...(baseDelay * 0.1))
        let delay = min(baseDelay + jitter, maxDelay)

        registrationTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let registration = try await self.register(deviceId: nil)

                if let context = self.deviceContext {
                    let accessToken = (try? self.secureStorage.getDeviceToken()) ?? ""
                    let expiresAt = Date().addingTimeInterval(3600)
                    await context.updateRegistered(
                        serverDeviceId: registration.id,
                        accessToken: accessToken,
                        expiresAt: expiresAt
                    )
                }

                if self.configuration.enableLogging {
                    self.logger.info("Silent registration retry succeeded on attempt \(attempt)")
                }
            } catch {
                if self.configuration.enableLogging {
                    self.logger.warning("Silent registration retry \(attempt) failed: \(error.localizedDescription)")
                }
                await self.deviceContext?.markFailed(error)
                self.scheduleRegistrationRetry(attempt: attempt + 1)
            }
        }
    }
}

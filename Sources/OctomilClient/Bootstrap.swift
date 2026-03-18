/// OctomilClient — single-import umbrella module.
///
/// Customers add one SPM dependency and write `import OctomilClient`.
/// All engine adapters are auto-registered on module load — no engine-specific
/// imports or registration calls needed in app code.
@_exported import Octomil

import OctomilRuntimeLlama
import OctomilRuntimeSherpa
import OctomilRuntimeWhisper

/// Auto-register all bundled engines on module load.
///
/// This runs once when the OctomilClient module is first imported.
/// The customer never needs to call this — it happens automatically.
/// MLX is opt-in — call `EngineRegistry.installMLX()` separately if linked.
private let _bootstrapEngines: Void = {
    let registry = EngineRegistry.shared
    registry.registerLlamaCpp()
    registry.registerSherpa()
    registry.registerWhisper()
}()

/// Ensures engine bootstrap has run. Called internally by SDK init paths
/// as a safety net in case module-load initialization is deferred.
public func ensureEnginesRegistered() {
    _ = _bootstrapEngines
}

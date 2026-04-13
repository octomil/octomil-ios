# Architecture — octomil-ios

## Repo Responsibility

Native Apple SDK (iOS 17+ / macOS 14+) for the Octomil platform. Owns:

- **Runtime / session management** — Engine lifecycle, model loading, inference sessions
- **Device profile** — Hardware detection (ANE, GPU, Neural Engine, memory, thermal state)
- **Planner** — Runtime planning and model selection per device capability
- **Hosted API client** — Chat, completions, embeddings, responses, model catalog
- **Unified facade** — Single entry point routing to local or cloud backends
- **Streaming** — SSE and async sequence streaming for inference
- **Telemetry** — OpenTelemetry-compatible span instrumentation
- **Device auth** — Token bootstrap, refresh, publishable key auth
- **Training** — Federated learning participant (on-device training rounds)

## Module Layout

```
Sources/Octomil/
├── Generated/           # Enum types from octomil-contracts — DO NOT HAND-EDIT
├── Runtime/             # Engine adapters, session management, kernel
├── Client/              # Hosted API client
├── Chat/                # Chat completions
├── Audio/               # Audio transcription
├── Text/                # Text generation helpers
├── Responses/           # Responses API
├── Streaming/           # SSE + async sequence streaming
├── Models/              # Model types, references, resolution
├── Manifest/            # Engine manifest types and resolution
├── Discovery/           # Model discovery and catalog
├── Analytics/           # Analytics and metrics
├── Telemetry/           # OpenTelemetry instrumentation
├── Security/            # Certificate pinning, integrity checks
├── Privacy/             # Privacy controls
├── Sync/                # State sync with control plane
├── Control/             # Control plane client
├── Training/            # Federated learning participant
├── Experiments/         # A/B experiment variants
├── Pairing/             # Device pairing
├── Personalization/     # On-device personalization
├── Workflows/           # Multi-step workflow orchestration
├── TryItOut/            # Interactive demo helpers
├── Wrapper/             # Compatibility wrappers
├── Utils/               # Shared utilities
├── Octomil.swift        # Main SDK entry point
├── DeviceAuth.swift     # Device authentication
├── DeviceInfo.swift     # Device capability detection
└── Version.swift        # SDK version constant

Tests/
├── OctomilTests/        # Unit tests
├── OctomilMLXTests/     # MLX engine-specific tests
└── OctomilTimeSeriesTests/  # Time series model tests
```

## Products (SPM)

- **OctomilClient** — Primary product. Single import for customers.
- **Octomil** — Backward-compatible direct core access.
- **OctomilClip** — CLIP model support.

## Boundary Rules

- **`Generated/` is read-only**: Machine-generated from `octomil-contracts`. Never hand-edit.
- **Runtime modules are optional**: Engine adapters (MLX, CoreML, MNN) guard their imports. Missing frameworks produce clear errors, not link-time crashes.
- **No UIKit in SDK core**: UI helpers belong in `TryItOut/` or the companion app (`octomil-app-ios`), not the SDK.
- **Streaming is protocol-based**: Engines conform to async sequence protocols; consumers don't know which engine is running.

## Public API Surfaces

- `import OctomilClient` — Primary entry point for SDK consumers
- `Octomil` class — Main facade (hosted + local routing)
- Chat, Responses, Embeddings, Audio APIs
- Async/await + Combine-compatible streaming

## Generated Code

Location: `Sources/Octomil/Generated/`

Generated from `octomil-contracts/enums/*.yaml` via codegen. All enum types (device platform, artifact format, runtime executor, thermal state, etc.) live here.

**Do not hand-edit.** Run codegen from `octomil-contracts` to update.

## Source-of-Truth Dependencies

| Dependency | Source |
|---|---|
| Enum definitions | `octomil-contracts/enums/*.yaml` |
| Engine manifest | `octomil-contracts/fixtures/core/engine_manifest.json` |
| API semantics | `octomil-contracts/schemas/` |
| Conformance tests | `octomil-contracts/conformance/` |

## Test Commands

```bash
# All tests
swift test

# Specific test
swift test --filter OctomilTests.SomeTestClass/testMethod

# Build only (no tests)
swift build

# Build for specific platform
swift build --sdk iphoneos
```

Tests use **XCTest** via Swift Package Manager.

## Review Checklist

- [ ] New enum value: was it added to `octomil-contracts` first, then regenerated?
- [ ] Runtime change: are optional framework imports guarded?
- [ ] New public API: is it accessible from `OctomilClient` product?
- [ ] Facade change: does it handle both hosted and local paths?
- [ ] Streaming: does it work with both async sequences and Combine?
- [ ] Platform: does it compile for both iOS 17 and macOS 14?
- [ ] Conformance: do conformance tests still pass?

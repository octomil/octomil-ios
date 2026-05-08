# iOS SDK Bloat Reduction Track

Reviewer: @tai

## Goal

Make the iOS SDK lighter for client users and reduce drift between SDK runtime, generated contracts, and companion app expectations.

## Findings

- `OctomilClient` is a heavy umbrella target that pulls bundled runtime modules and binary engine targets into simple client work.
- Generated capabilities and app-local capability state can drift.
- The SDK exposes public try-it-out UI while the app also carries separate chat, transcription, and prediction flows.
- Deep-link/profile behavior overlaps with the app but is not fully shared.
- Local `.build` and example build directories account for multiple GB of ignored output.

## Proposed Cleanup

- Split client-only, UI, and runtime-heavy products so basic hosted usage has a smaller dependency graph.
- Make generated contract types the source of truth for model capability and runtime metadata.
- Decide whether try-it-out UI lives in the SDK, app, or a shared sample module.
- Share pairing/deep-link/profile parsing with the companion app.
- Document external build dirs and cleanup commands for local SwiftPM/Xcode artifacts.

## Validation

```bash
swift package describe
swift test
rg -n 'Product|OctomilClient|DeepLinkHandler|ModelCapability|TryItOut' Package.swift Sources Tests
```

# Epic: Adopt the generated swift-openapi client (octomil-ios)

Status: Proposed
Owner: TBD
Related: octomil-ios#231 (gate narrowed to spec-copy), octomil-contracts#192
(deterministic spec), #189/#190/#191/#193 (generator hardening)

## 1. Summary

octomil-ios ships an OpenAPI contract dependency (`swift-openapi-generator`
1.12.2, plus `swift-openapi-runtime` / `swift-openapi-urlsession`) but does
**not** actually use a generated client. The committed
`Sources/Octomil/Client.swift` and `Sources/Octomil/Types.swift` are
hand-maintained shims that were mislabeled as generator output. All real
networking is hand-written in the facade (`APIClient` + friends) on top of
raw `URLSession`. This epic adopts the real generated transport so request
and response shapes are contract-derived (can't silently drift), matching the
strategy already shipped on the Node/Browser/Python/Android SDKs.

This is a facade rework, not a file move. It is explicitly out of scope for
the freshness gate (see #231).

## 2. Goals

- Generate the OpenAPI client + types from `dist/openapi.yaml` via
  swift-openapi-generator 1.12.2 into a single, committed, gated directory.
- Route the SDK's HTTP calls through the generated client (or a thin adapter
  over it) so request/response types come from the contract.
- Re-enable a real freshness gate: regenerate in CI and `git diff` the
  generated directory (replacing the spec-copy-only gate from #231).
- Preserve the public SDK surface and behavior (the hand-written facade
  ergonomics, typed `OctomilError`, retry/idempotency, streaming, local
  runtime routing) — bind to generated types only where the SDK is a
  pass-through, keep facades where it reshapes (see the
  `sdk_facade_vs_generated_binding_rule` convention).

## 3. Non-goals

- No change to the public API of `OctomilClient` / the facade classes.
- No migration of the contract **domain enums** in
  `Sources/Octomil/Generated/` (those are produced by octomil-contracts
  `codegen/generate.py --lang swift`, vendored here, and drift-gated by the
  contracts repo's own `codegen/generate.py --check`). They stay as-is.
- No server-side or other-SDK changes.

## 4. Current state (facts to design against)

- `Sources/Octomil/Client.swift` (placeholder protocol) and
  `Sources/Octomil/Types.swift` are HAND-MAINTAINED shims (relabeled in
  #231). `Types.swift` defines `_OctomilAPIErrorPayload`, consumed by
  `OctomilError.from(apiPayload:)` (`Sources/Octomil/Client/OctomilError.swift:675`)
  to map API error bodies to typed `OctomilError`.
- Networking is hand-rolled: `Sources/Octomil/Client/APIClient.swift` holds a
  `URLSession` and generic helpers `postJSON` / `getJSON` /
  `performRequest<T: Decodable>` + `configureHeaders`. Per-area clients
  (`APIClient+Models`, `+Telemetry`, `DeviceProfileClient`,
  `EmbeddingClient`, `RoutingClient`, …) build `URLRequest`s by hand against
  `baseURL + path`.
- `Sources/Octomil/Generated/` = 72 contract domain-enum files
  (`DevicePlatform`, `ArtifactFormat`, …), banner
  `// Auto-generated from octomil-contracts`. NOT swift-openapi output.
- `Sources/Octomil/openapi.yaml` = vendored contract spec copy; freshness is
  gated by `.github/workflows/openapi-types-fresh.yml` (#231).
- `octomil-contracts/tools/sdkgen/generate-swift.sh` runs the
  swift-openapi-generator **command** plugin
  (`generate-code-from-openapi --target Octomil`); under 1.12.2 it writes
  `Client.swift` + `Types.swift` into a `GeneratedSources/` subdir. The
  script is currently unused by the gate (and its `OUT` still points at the
  wrong dir — fix as part of this epic).
- Known build hazard: the module surfaces Swift-6-language-mode warnings
  ("`AnyCodable` non-Sendable", "`lock`/`unlock` from async context") that
  become errors under Swift 6 mode. The generated client must not flip the
  module into Swift 6 mode (or those must be fixed first).

## 5. Design decisions to make

1. **Output directory + committed vs build-time.** Pick ONE:
   - (a) COMMAND plugin → commit `Sources/Octomil/GeneratedSources/` and gate
     it (regenerate-and-diff). Deterministic now that the contracts spec is
     sorted (#192). Recommended — mirrors the other SDKs.
   - (b) BUILD (prebuild) plugin → regenerate into derived data at build time,
     commit nothing, gate becomes "builds clean." Lighter to maintain but no
     committed artifact to review.
   Decide and make `generate-swift.sh` `OUT`, the banner loop, the
   `git status` summary, and the gate diff all target that one dir.

2. **Custom types relocation.** Move `_OctomilAPIErrorPayload` (and any other
   hand types currently in the shims) into a clearly hand-owned file
   (e.g. `Sources/Octomil/Client/APIErrorPayload.swift`) BEFORE deleting the
   shims, so `OctomilError.from(apiPayload:)` keeps compiling. Decide whether
   to bridge from the generated error schema (`ErrorPayload`/`ErrorEnvelope`)
   instead.

3. **Facade adoption depth.** Decide per area:
   - Bind request/response models to generated `Components.Schemas.*` where
     the facade is a pass-through.
   - Keep hand-written request/response shapes where the facade reshapes
     (camelCase vs wire, separate method args, ergonomic unions) — binding
     there would make the type lie. Same rule used for the TS/Python SDKs.
   - Choose: call the generated `Client` operations directly, or keep
     `APIClient`'s URLSession transport and only adopt the generated *types*.
     (Adopting types-only is lower-risk and still kills shape drift.)

4. **Generator config.** Settle `openapi-generator-config.yaml`
   (`generate: [types, client]`, `accessModifier: internal`) and the
   access level needed for the facade to consume it.

5. **Banner / freshness.** Generated files must carry the stable banner from
   #189 (no abs path, no `@SHA`). Re-point / rewrite
   `scripts/check_openapi_banner.sh` (currently assumes `Generated/`) at the
   real generated dir.

## 6. Proposed plan (phased)

- **P0 — De-risk the toolchain.** Confirm 1.12.2 output compiles under the
  project's Swift mode; resolve the Sendable/lock warnings-as-errors or pin
  the language mode. Spike: generate into a scratch dir and `swift build`.
- **P1 — Relocate custom types.** Move `_OctomilAPIErrorPayload` out of the
  shim into a hand-owned file; keep `OctomilError.from(apiPayload:)` green.
  Delete the shim `Client.swift`/`Types.swift`. (One-time; build stays green.)
- **P2 — Wire generation.** Fix `generate-swift.sh` `OUT` + banner + summary
  to the chosen dir; generate; commit the output with the stable banner;
  `swift build`.
- **P3 — Adopt types in the facade.** Replace hand-typed request/response
  models with generated `Components.Schemas.*` where pass-through; leave
  facades where reshaping. Update call sites; keep public API identical.
- **P4 — Re-enable the real gate.** Flip `.github/workflows/openapi-types-fresh.yml`
  back to: run the generator, `git diff` the generated dir + `openapi.yaml`,
  run the banner check, `swift build`. Keep the strict spec→server gate.
  (This supersedes the spec-copy-only gate from #231.)

## 7. Acceptance criteria

- Generated client+types live in one committed (or build-time) dir with the
  stable AUTOGENERATED banner; no `multiple producers` collision; no
  mislabeled hand files.
- `swift build` + `swift test` pass; public API unchanged (no consumer break).
- `openapi-types-fresh` regenerates and diffs the generated dir and stays
  green on a no-op contract commit (determinism holds).
- Request/response shapes for pass-through endpoints are contract-derived;
  facade reshaping points are documented as intentional.

## 8. Risks

- Swift 6 language-mode warnings-as-errors in existing hand code may block a
  clean build once the generated client is added (P0 must settle this).
- swift-openapi-generator output shape changed between 1.6.0 and 1.12.2;
  facade adaptation (P3) is the real cost, not file placement.
- The generated client's transport vs the facade's bespoke `URLSession`
  (retry/idempotency/streaming/local-runtime routing) — adopting the
  generated `Client` wholesale may not preserve those; types-only adoption
  avoids that.

## 9. Out of scope / follow-ups

- Contract domain enums (`Generated/`) — owned and gated by octomil-contracts.
- Any cross-SDK or server change.

# Native runtime layer

Swift mirror of the `octomil-runtime` C ABI (`octomil-runtime/include/octomil/runtime.h`). Two implementations conform to the same protocol surface:

- **Stub** (`StubRuntime.swift`) — Sprint 1, in-process actor emitting a scripted event timeline. Unblocks the iPad demo's lifecycle + telemetry path.
- **FFI** — Sprint 2, real cross-compiled XCFramework + `@convention(c)` callback. Drops in by swapping the conforming type.

The protocol surface is locked to python's `octomil/runtime/native/loader.py:359–648` (the `_CDEF` block). Any change here requires a matched python change first; otherwise drift accumulates that Approach B will pay for at swap time.

References:
- Spec: `docs/specs/2026-05-06-ios-stub-runtime.md`
- Spike: `docs/spikes/2026-05-06-ios-xcframework-spike.md`
- Linear: OCT-104 (parent), OCT-78 / OCT-97 (parity)

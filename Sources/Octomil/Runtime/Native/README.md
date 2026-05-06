# Native runtime layer

Swift mirror of the `octomil-runtime` C ABI (`octomil-runtime/include/octomil/runtime.h`). Two implementations conform to the same protocols: a Sprint 1 in-process stub, and a Sprint 2 real FFI binding.

## Where this fits

```
+-----------------------------------------------------------------+
|  Demo UI  |  Canary rollout  |  Telemetry dashboard             |
+-----------------------------------------------------------------+
                                 |
                                 v
+-----------------------------------------------------------------+
|  Native protocol surface (Swift)                                |
|  NativeRuntime / NativeModel / NativeSession                    |
|  locked 1:1 to python loader.py _CDEF                           |
+-----------------------------------------------------------------+
                                 |
                                 v
+-----------------------------------------------------------------+
|  Sprint 1 (this PR):                                            |
|    StubRuntime  -- in-process actor, scripted timeline,         |
|                    synthesized telemetry; no inference          |
|                                                                 |
|  Sprint 2 (planned):                                            |
|    FFIRuntime   -- @convention(c) wrapper around                |
|                    cross-compiled octomil_runtime.xcframework   |
+-----------------------------------------------------------------+
                                 |
                                 |  lifecycle + telemetry events
                                 v
+-----------------------------------------------------------------+
|  Real on-device inference engines  (unchanged Sprint 1 -> 2)    |
|  llama, sherpa-onnx, whisper, onnxruntime, CoreML, MLX          |
|  wired today via Package.swift binaryTargets;                   |
|  iPad runs real STT -> LLM -> TTS offline through these.        |
+-----------------------------------------------------------------+
```

The middle box is the **swap seam**. Only that layer changes between Sprint 1 and Sprint 2 — consumers above the protocol surface and engines below are identical across both.

## Why a stub in Sprint 1

`octomil-runtime/CMakeLists.txt` has no iOS toolchain wiring; `BUILD.md` punts iOS to "slice 4". A real XCFramework cross-compile + `@convention(c)` Swift wrapper is 6–8 hr minimum, and absorbing that into Sprint 1's budget would cost the dashboard/canary deliverable.

The demo still legitimately runs offline inference: `octomil-ios/Package.swift:139–158` already binds `llama`, `sherpa-onnx`, `whisper`, and `onnxruntime` XCFrameworks, and the iPad runs actual STT → LLM → TTS through those engines. The stub fakes only the orchestration + telemetry layer that the C runtime would normally provide — not audio in or audio out.

## Contract

The Swift protocol surface is locked to python's `octomil/runtime/native/loader.py:359–648` (the `_CDEF` block). Any change here requires a matched python change first; otherwise drift accumulates that Approach B will pay for at swap time.

## References

- Spec: `docs/specs/2026-05-06-ios-stub-runtime.md`
- Spike: `docs/spikes/2026-05-06-ios-xcframework-spike.md`
- Linear: OCT-104 (parent), OCT-78 / OCT-97 (parity)

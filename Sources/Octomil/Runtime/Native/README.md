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
|  Sprint 1:                                                      |
|    StubRuntime  -- in-process actor, scripted timeline,         |
|                    synthesized telemetry; no inference          |
|                                                                 |
|  Sprint 2a:                                                     |
|    FFINativeRuntime -- dlopen/dlsym wrapper for runtime open,   |
|                        capability discovery, ABI/size checks,   |
|                        close, and last-error status mapping     |
|                                                                 |
|  Sprint 2b (planned):                                           |
|    FFINativeRuntime -- model/session/event bindings around      |
|                        cross-compiled octomil_runtime.xcframework |
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

## Current native bridge scope

`FFINativeRuntime` dynamically loads `liboctomil_runtime` from:

- the explicit `libraryPath` passed to `FFINativeRuntime.open(...)`
- `OCTOMIL_RUNTIME_LIBRARY`
- app private frameworks / `liboctomil_runtime.dylib` default lookup paths

It validates `oct_runtime_abi_version_major/minor`, `oct_runtime_config_size`, and `oct_capabilities_size` before calling `oct_runtime_open`. If the library, a required symbol, ABI version, or struct size is unavailable, the bridge throws `NativeRuntimeError` and does not fall back to `StubRuntime`.

The bridge currently supports only `oct_runtime_open`, `oct_runtime_capabilities`, `oct_runtime_capabilities_free`, `oct_runtime_close`, `oct_runtime_last_error`, and `oct_last_thread_error`. `openModel` and `openSession` fail closed with `.unsupported` until the model/session/event ABI is wired and tested. Passing a telemetry sink is also rejected because event marshalling is not implemented yet.

## Why a stub remains

The iOS package still does not ship a cross-compiled `octomil_runtime.xcframework`. Without that packaging, native conformance lifecycle tests cannot honestly run model/session/event paths.

The demo still legitimately runs offline inference: `octomil-ios/Package.swift:139–158` already binds `llama`, `sherpa-onnx`, `whisper`, and `onnxruntime` XCFrameworks, and the iPad runs actual STT → LLM → TTS through those engines. The stub fakes only the orchestration + telemetry layer that the C runtime would normally provide — not audio in or audio out.

## Contract

The Swift protocol surface is locked to python's `octomil/runtime/native/loader.py:359–648` (the `_CDEF` block). Any change here requires a matched python change first; otherwise drift accumulates that Approach B will pay for at swap time.

## References

- Spec: `docs/specs/2026-05-06-ios-stub-runtime.md`
- Spike: `docs/spikes/2026-05-06-ios-xcframework-spike.md`
- Linear: OCT-104 (parent), OCT-78 / OCT-97 (parity)

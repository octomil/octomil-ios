# Octomil iOS SDK — Samples

Small SwiftUI samples for the three most common Octomil app capabilities.

| Sample | Capability | Key SDK API |
|--------|-----------|-------------|
| [ChatSample](ChatSample/) | Text generation | `OctomilChat.stream()` |
| [TranscriptionSample](TranscriptionSample/) | Speech-to-text | `client.audio.transcriptions.create()` |
| [PredictionSample](PredictionSample/) | Next-word prediction | `client.text.predictions.create()` |

## Prerequisites

1. Org API credentials from [app.octomil.com](https://app.octomil.com)
2. One deployed model per capability:
   - **Chat**: e.g. `phi-4-mini` (llama.cpp)
   - **Transcription**: e.g. `whisper-small` (whisper.cpp) — also add a `test_audio.wav` to the TranscriptionSample bundle
   - **Prediction**: e.g. `smollm2-135m` (llama.cpp)
3. Replace `YOUR_ORG_ID`, `YOUR_API_KEY`, and any placeholder model IDs before running.

## Running a sample

```bash
cd Examples/ChatSample   # or TranscriptionSample / PredictionSample
open Package.swift       # opens in Xcode
# Select a real iPhone or iPad target, then run
```

These are device examples, not simulator-first demos. If a runtime works in the simulator, treat that as a convenience, not the main path.

## These samples vs. the companion app

| | SDK Samples (here) | [Companion App](https://github.com/octomil/octomil-app-ios) |
|---|---|---|
| Purpose | Show the shortest useful integration for one capability | Evaluate models on-device and exercise the full phone-side flow |
| Scope | One capability per sample, minimal UI, minimal setup | All capabilities, pairing, discovery, recovery, golden tests |
| Audience | SDK adopters adding Octomil to their app | Internal testing, demos, and device lab workflows |

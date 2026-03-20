# Octomil iOS SDK — Samples

Minimal, copyable examples for the main Octomil capabilities.

| Sample | Capability | Key SDK API |
|--------|-----------|-------------|
| [ChatSample](ChatSample/) | Text generation | `OctomilChat.stream()` |
| [TranscriptionSample](TranscriptionSample/) | Speech-to-text | `client.audio.transcriptions.create()` |
| [PredictionSample](PredictionSample/) | Next-word prediction | `client.text.predictions.create()` |

## Prerequisites

1. An Octomil account with API credentials ([app.octomil.com](https://app.octomil.com))
2. At least one model deployed per capability:
   - **Chat**: e.g. `phi-4-mini` (llama.cpp)
   - **Transcription**: e.g. `whisper-small` (whisper.cpp) — also add a `test_audio.wav` to the TranscriptionSample bundle
   - **Prediction**: e.g. `smollm2-135m` (llama.cpp)
3. Replace `YOUR_ORG_ID` and `YOUR_API_KEY` in each sample before running.

## Running a sample

```bash
cd Examples/ChatSample   # or TranscriptionSample / PredictionSample
open Package.swift       # opens in Xcode
# Set a valid iOS Simulator or device target, then ⌘R
```

## These samples vs. the companion app

| | SDK Samples (here) | [Companion App](https://github.com/octomil/octomil-app-ios) |
|---|---|---|
| Purpose | Show the shortest integration path for each capability | Full evaluation and dogfood app |
| Scope | One capability per sample, ~100 lines each | All capabilities, pairing, discovery, golden tests |
| Audience | SDK adopters adding Octomil to their app | Internal testing and device lab |

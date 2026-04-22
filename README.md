# Octomil iOS

Run AI models on-device. CoreML and MLX inference with one API, automatic Neural Engine benchmarking, streaming generation, and OTA model updates.

[![CI](https://github.com/octomil/octomil-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/octomil/octomil-ios/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/octomil/octomil-ios)](LICENSE)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Foctomil%2Foctomil-ios%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/octomil/octomil-ios)

## What is this?

A Swift SDK that handles everything between your app and an on-device ML model. Load a CoreML or MLX model, get automatic Neural Engine vs CPU benchmarking, streaming token generation, telemetry, OTA updates, and smart cloud/device routing -- without writing any of that infrastructure yourself. 100% Swift, zero dependencies in the core module.

## Installation

**Swift Package Manager** -- add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/octomil/octomil-ios.git", from: "1.3.0")
]
```

Or in Xcode: File > Add Package Dependencies > paste `https://github.com/octomil/octomil-ios.git`.

Four library products available:

| Product | What it adds |
|---------|-------------|
| `Octomil` | Core SDK -- CoreML inference, telemetry, model management. Zero dependencies. |
| `OctomilMLX` | MLX LLM inference via [mlx-swift](https://github.com/ml-explore/mlx-swift). |
| `OctomilTimeSeries` | Time series forecasting engine. |
| `OctomilClip` | App Clip pairing flow. |

## Quick Start (Unified Facade)

```swift
import OctomilClient

let client = Octomil(publishableKey: "oct_pub_live_...")
try await client.initialize()
let response = try await client.responses.create(model: "phi-4-mini", input: "Hello")
print(response.outputText)
```

### Embeddings

```swift
let result = try await client.embeddings.create(
    model: "nomic-embed-text-v1.5",
    input: "On-device AI inference at scale"
)
print(Array(result.embeddings[0].prefix(5)))
```

### Migrating from OctomilClient

`OctomilClient` and the low-level `OctomilResponses` / `ResponseRequest` APIs still work exactly as before. The `Octomil` facade is a convenience wrapper for the cloud-backed Responses path. For local CoreML inference, continue using `Deploy.model()` and `OctomilCoreML.wrap()`.

## Local Inference

### CoreML inference (5 lines)

```swift
import Octomil

let model = try await Deploy.model(
    at: Bundle.main.url(forResource: "MobileNet", withExtension: "mlmodelc")!
)

let result = try model.predict(inputs: ["image": pixelBuffer])

print(model.activeDelegate)   // "neural_engine" or "cpu" (auto-selected)
print(model.warmupResult!)    // cold: 45ms, warm: 3ms, cpu: 12ms
```

`Deploy.model` loads the model, runs a warmup benchmark comparing Neural Engine vs CPU, and picks the fastest delegate. No configuration needed.

### MLX LLM streaming (6 lines)

```swift
import OctomilMLX

let llm = try await Deploy.mlxModel(at: modelDirectory)

let (stream, getResult) = llm.predictStream(prompt: "Explain quicksort in Swift")
for try await chunk in stream {
    print(String(data: chunk.data, encoding: .utf8)!, terminator: "")
}
let metrics = getResult()  // ttfcMs, throughput, totalChunks
```

## Features

### Drop-in wrapper for existing CoreML models

Already using `MLModel` directly? Wrap it in one line to get telemetry, input validation, and OTA updates with zero call-site changes:

```swift
// Before
let model = try MLModel(contentsOf: modelURL)
let output = try model.prediction(from: input)

// After
let model = try OctomilCoreML.wrap(MLModel(contentsOf: modelURL), modelId: "classifier")
let output = try model.predict(input: input)  // same result, now with telemetry + OTA
```

### Adaptive inference

Automatically switches compute units (ANE/GPU/CPU) based on battery, thermal pressure, and memory:

```swift
let model = try await Deploy.adaptiveModel(from: modelURL)
let result = try await model.predict(input: features)
// Downgrades from Neural Engine to CPU under thermal pressure
// Throttles inference rate in Low Power Mode
```

### Streaming across modalities

Text, image, audio, and video generation with per-chunk latency tracking:

```swift
let (stream, getResult) = model.predictStream(input: prompt, modality: .text)
for try await chunk in stream {
    print(chunk.data, chunk.latencyMs)
}
let result = getResult()
// result.ttfcMs, result.throughput, result.avgChunkLatencyMs
```

### Smart routing (device vs cloud)

Route inference on-device or to the cloud based on device capabilities:

```swift
let model = try OctomilCoreML.wrap(MLModel(contentsOf: url), modelId: "classifier")
model.configureRouting(RoutingConfig(serverURL: apiURL, apiKey: key))
// Automatically routes to cloud when device is constrained
// Falls back to local CoreML on any cloud failure
```

### A/B experiments

Deterministic experiment assignment with metric tracking:

```swift
let experiments = ExperimentsClient(apiClient: client.apiClient)
let variant = experiments.getVariant(experiment: exp, deviceId: deviceId)
try await experiments.trackMetric(
    experimentId: exp.id, metricName: "accuracy", metricValue: 0.94
)
```

### Federated training

On-device training with weight extraction, battery/thermal gating, and offline gradient caching:

```swift
let result = try await trainer.trainIfEligible(
    model: model,
    dataProvider: { trainingBatch },
    config: TrainingConfig(epochs: 3, learningRate: 0.001),
    deviceState: await monitor.currentState
)
// Skips training if battery < 20% or thermal state is serious
// Caches gradients offline when network is unavailable
```

### Server integration

Full lifecycle: register device, download models, run inference, upload training results:

```swift
let client = OctomilClient(
    deviceAccessToken: "<device-token>",
    orgId: "org_123",
    serverURL: URL(string: "https://api.octomil.com")!
)
let registration = try await client.register()
let model = try await client.downloadModel(modelId: "fraud_detection")
```

## Supported Models

| Format | Engine | Use case |
|--------|--------|----------|
| `.mlmodelc` / `.mlmodel` / `.mlpackage` | CoreML (Neural Engine, GPU, CPU) | Vision, classification, regression |
| MLX safetensors | MLX via [mlx-swift](https://github.com/ml-explore/mlx-swift) | LLM text generation |
| Time series | MLX-Swift-TS | Forecasting |

HuggingFace Hub models can be loaded directly for development:

```swift
let llm = try await Deploy.mlxModelFromHub(modelId: "mlx-community/Llama-3.2-1B-Instruct-4bit")
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Architecture

```
Sources/
  Octomil/           Core SDK (zero dependencies)
    Deploy/          Model loading, benchmarking, adaptive inference
    Wrapper/         Drop-in MLModel wrapper with telemetry + OTA
    Inference/       Streaming engines (text, image, audio, video)
    Client/          Server API client, routing, certificate pinning
    Training/        Federated trainer, weight extraction, gradient cache
    Runtime/         Device state monitor, adaptive model loader
    Experiments/     A/B experiment client
    Telemetry/       Batched event reporting
    Security/        Secure aggregation (SecAgg+, Shamir)
    Privacy/         Differential privacy configuration
  OctomilMLX/        MLX LLM inference (mlx-swift dependency)
  OctomilTimeSeries/ Time series forecasting
  OctomilClip/       App Clip pairing UI
```

## vs. raw CoreML

| | Raw CoreML | Octomil |
|---|---|---|
| Load + predict | ~15 lines | 3 lines |
| Neural Engine benchmarking | Manual | Automatic |
| Streaming generation | Build it yourself | Built in |
| OTA model updates | Build it yourself | One config flag |
| Telemetry / latency tracking | Build it yourself | Automatic |
| Adaptive compute switching | Build it yourself | `Deploy.adaptiveModel` |
| A/B model experiments | Build it yourself | `ExperimentsClient` |
| Smart device/cloud routing | Build it yourself | `configureRouting()` |

## AppManifest and Control Plane

The iOS SDK uses a **hybrid model**: your app declares what it can consume via `AppManifest` in code, and the Octomil control plane decides which specific model version each device gets.

`AppManifest` is a Swift struct — not a config file. You instantiate it in code:

```swift
import Octomil

// 1. Create client with auth
let client = OctomilClient(auth: .publishableKey("oct_pub_live_..."))

// 2. Declare capabilities and delivery modes
let manifest = AppManifest(models: [
    AppModelEntry(id: "chat-model", capability: .chat, delivery: .managed),
    AppModelEntry(id: "transcription", capability: .transcription, delivery: .managed),
    AppModelEntry(id: "classifier", capability: .classification, delivery: .bundled,
                  bundledPath: "models/classifier.mlmodelc"),
])

// 3. Configure — bootstraps catalog, registers device, starts desired-state polling
try await client.configure(manifest: manifest, auth: .publishableKey("oct_pub_live_..."), monitoring: .enabled)
```

**Delivery modes:**

| Mode | Behaviour |
|------|-----------|
| `.managed` | Control plane assigns the model version. SDK downloads, caches, and updates it via `ArtifactReconciler`. |
| `.bundled` | Model is included in the app binary at `bundledPath`. No control plane involvement. |
| `.cloud` | Inference routes to a cloud provider. No local artifact. |

After `configure()`, the SDK registers the device, starts polling desired state via `ArtifactReconciler`, downloads assigned artifacts with SHA-256 verification, and registers runtimes as models become ready. Use `client.catalog.runtime(for: .chat)` to resolve the runtime by capability.

## Samples

Minimal examples for the three main mobile SDK capabilities:

| Sample | Capability | Key API |
|--------|-----------|---------|
| [ChatSample](Examples/ChatSample/) | Text generation | `OctomilChat.stream()` |
| [TranscriptionSample](Examples/TranscriptionSample/) | Speech-to-text | `client.audio.transcriptions.create()` |
| [PredictionSample](Examples/PredictionSample/) | Next-word prediction | `client.text.predictions.create()` |

Each sample is a standalone SwiftUI app focused on one capability. Open `Package.swift` in Xcode and run it on a real device. A simulator is fine for UI smoke testing, but deployed-model flows should be validated on hardware.

**Prerequisites:** Org API credentials, one deployed model per capability, and a bundled `test_audio.wav` for the transcription sample. See [Examples/README.md](Examples/README.md) for setup.

> **Need the full device app?** The [Octomil iOS App](https://github.com/octomil/octomil-app-ios) is the broader evaluation app for model testing, pairing, recovery, and golden-path automation. These samples are intentionally narrower: one feature, minimal setup, copyable code.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

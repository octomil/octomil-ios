<p align="center">
  <strong>Octomil iOS</strong><br>
  On-device ML for iPhone and iPad.
</p>

<p align="center">
  <a href="https://github.com/octomil/octomil-ios/actions/workflows/ci.yml"><img src="https://github.com/octomil/octomil-ios/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/octomil/octomil-ios/actions/workflows/codeql.yml"><img src="https://github.com/octomil/octomil-ios/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/octomil/octomil-ios/blob/main/LICENSE"><img src="https://img.shields.io/github/license/octomil/octomil-ios" alt="License"></a>
  <a href="https://swiftpackageindex.com/octomil/octomil-ios"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Foctomil%2Foctomil-ios%2Fbadge%3Ftype%3Dplatforms" alt="Platforms"></a>
</p>

---

## Install

```swift
dependencies: [
    .package(url: "https://github.com/octomil/octomil-ios.git", from: "1.1.0")
]
```

Swift 5.9+. Zero external dependencies.

## Quick Start

Deploy a CoreML model and run inference locally. No server needed:

```swift
import Octomil

let model = try Deploy.model(
    at: Bundle.main.url(forResource: "MobileNet", withExtension: "mlmodelc")!
)

let result = try model.predict(input: features)

print(model.activeDelegate)  // "neural_engine"
print(model.warmupResult!)   // cold: 45ms, warm: 3ms
```

## Server Integration

Connect to the Octomil platform for model management and federated learning:

```swift
let client = OctomilClient(
    deviceAccessToken: "<device-token>",
    orgId: "org_123",
    serverURL: URL(string: "https://api.octomil.com")!
)

let registration = try await client.register()
let model = try await client.downloadModel(modelId: "fraud_detection")
let prediction = try model.predict(input: inputFeatures)
```

## Streaming Inference

Multi-modal streaming with automatic latency tracking:

```swift
for try await chunk in model.stream(input: features) {
    print(chunk.data, chunk.latencyMs)
}
// Tracks TTFC, throughput, and total duration per session
// Supports text, image, audio, and video modalities
```

## Highlights

- CoreML + Neural Engine with automatic delegate benchmarking
- Streaming inference across text, image, audio, and video
- Federated learning with secure aggregation (SecAgg+, Shamir secret sharing)
- On-device personalization (Ditto, FedPer)
- Battery and network aware training
- Certificate pinning, Keychain token storage
- mDNS discovery for `octomil deploy --phone`
- 100% Swift, zero dependencies

## Documentation

[docs.octomil.com/sdks/ios](https://docs.octomil.com/sdks/ios)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

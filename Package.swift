// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "octomil-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Primary product — single import for customers
        .library(
            name: "OctomilClient",
            targets: ["OctomilClient"]
        ),
        // Backward-compatible product (direct core access)
        .library(
            name: "Octomil",
            targets: ["Octomil"]
        ),
        .library(
            name: "OctomilClip",
            targets: ["OctomilClip"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.25.4"),
        .package(url: "https://github.com/kunal732/MLX-Swift-TS", revision: "8659cf20c4382e94233e4de287e68f6e575fef23"),
    ],
    targets: [
        // ──────────────────────────────────────────────
        // Public umbrella — re-exports Octomil
        // ──────────────────────────────────────────────
        .target(
            name: "OctomilClient",
            dependencies: [
                "Octomil",
                "OctomilRuntimeLlama",
                "OctomilRuntimeSherpa",
                "OctomilRuntimeWhisper",
                "OctomilMLX",
                "OctomilTimeSeries",
            ],
            path: "Sources/OctomilClient"
        ),

        // ──────────────────────────────────────────────
        // Core SDK
        // ──────────────────────────────────────────────
        .target(
            name: "Octomil",
            dependencies: [],
            path: "Sources/Octomil"
        ),

        // ──────────────────────────────────────────────
        // Engine adapters (internal to OctomilClient)
        // ──────────────────────────────────────────────
        .target(
            name: "OctomilRuntimeLlama",
            dependencies: ["Octomil", "llama"],
            path: "Sources/OctomilRuntimeLlama"
        ),
        .target(
            name: "OctomilRuntimeSherpa",
            dependencies: ["Octomil", "sherpa_onnx", "onnxruntime"],
            path: "Sources/OctomilRuntimeSherpa"
        ),
        .target(
            name: "OctomilRuntimeWhisper",
            dependencies: ["Octomil", "whisper"],
            path: "Sources/OctomilRuntimeWhisper"
        ),
        .target(
            name: "OctomilMLX",
            dependencies: [
                "Octomil",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/OctomilMLX"
        ),
        .target(
            name: "OctomilTimeSeries",
            dependencies: [
                "Octomil",
                .product(name: "MLXTimeSeries", package: "MLX-Swift-TS"),
            ],
            path: "Sources/OctomilTimeSeries"
        ),

        // ──────────────────────────────────────────────
        // Companion targets
        // ──────────────────────────────────────────────
        .target(
            name: "OctomilClip",
            dependencies: ["Octomil"],
            path: "Sources/OctomilClip"
        ),

        // ──────────────────────────────────────────────
        // Binary targets — pre-built C engine XCFrameworks
        // ──────────────────────────────────────────────
        // Hosted on GitHub Releases. Checksums populated after build.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/llama.xcframework.zip",
            checksum: "7454c373c8de8d485f697cac8a280738a5670d97f9923f08fa03cde877267032"
        ),
        .binaryTarget(
            name: "sherpa_onnx",
            url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/sherpa_onnx.xcframework.zip",
            checksum: "9e5c00ca3558052b1ebc2de9ffb802edd09e6d962de16f7554e7246be5a4530d"
        ),
        .binaryTarget(
            name: "onnxruntime",
            url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/onnxruntime.xcframework.zip",
            checksum: "a279301ca03a7070f2588144105ccc0e058523e2b25c70e1e8f4dea16fa08901"
        ),
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/whisper.xcframework.zip",
            checksum: "324d8143ae9ebf7d313288079bb67c7ba86088ef262c3a2340529b84a3278aaa"
        ),

        // ──────────────────────────────────────────────
        // Tests
        // ──────────────────────────────────────────────
        .testTarget(
            name: "OctomilTests",
            dependencies: ["Octomil"],
            path: "Tests/OctomilTests"
        ),
        .testTarget(
            name: "OctomilMLXTests",
            dependencies: ["OctomilMLX"],
            path: "Tests/OctomilMLXTests"
        ),
        .testTarget(
            name: "OctomilTimeSeriesTests",
            dependencies: ["OctomilTimeSeries"],
            path: "Tests/OctomilTimeSeriesTests"
        ),
    ]
)

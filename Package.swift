// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// MARK: - Default dependencies (no MLX)

var dependencies: [Package.Dependency] = []

var products: [Product] = [
    .library(name: "OctomilClient", targets: ["OctomilClient"]),
    .library(name: "Octomil", targets: ["Octomil"]),
    .library(name: "OctomilClip", targets: ["OctomilClip"]),
]

var targets: [Target] = [
    // Public umbrella — re-exports Octomil, registers all default engines
    .target(
        name: "OctomilClient",
        dependencies: [
            "Octomil",
            "OctomilRuntimeLlama",
            "OctomilRuntimeSherpa",
            "OctomilRuntimeWhisper",
        ],
        path: "Sources/OctomilClient"
    ),

    // Core SDK
    .target(
        name: "Octomil",
        dependencies: [],
        path: "Sources/Octomil"
    ),

    // Engine adapters
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

    // Companion targets
    .target(
        name: "OctomilClip",
        dependencies: ["Octomil"],
        path: "Sources/OctomilClip"
    ),

    // Binary targets — pre-built C engine XCFrameworks
    .binaryTarget(
        name: "llama",
        url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/llama.xcframework.zip",
        checksum: "7454c373c8de8d485f697cac8a280738a5670d97f9923f08fa03cde877267032"
    ),
    .binaryTarget(
        name: "sherpa_onnx",
        url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/sherpa_onnx.xcframework.zip",
        checksum: "0e38c2bde75435b884e4d8e573a71ac3e40cebc857e795c152ee858da3838174"
    ),
    .binaryTarget(
        name: "onnxruntime",
        url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/onnxruntime.xcframework.zip",
        checksum: "dde8b761b4afbc78c9b7092504db9d313360c8a10fa59d38f71f247676fef263"
    ),
    .binaryTarget(
        name: "whisper",
        url: "https://github.com/octomil/octomil-ios/releases/download/engines-v1/whisper.xcframework.zip",
        checksum: "324d8143ae9ebf7d313288079bb67c7ba86088ef262c3a2340529b84a3278aaa"
    ),

    // Tests
    .testTarget(
        name: "OctomilTests",
        dependencies: ["Octomil"],
        path: "Tests/OctomilTests"
    ),
]

// MARK: - Opt-in MLX (set OCTOMIL_ENABLE_MLX=1 to include)

if ProcessInfo.processInfo.environment["OCTOMIL_ENABLE_MLX"] != nil {
    dependencies += [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.25.4"),
        .package(url: "https://github.com/kunal732/MLX-Swift-TS",
                 revision: "8659cf20c4382e94233e4de287e68f6e575fef23"),
    ]
    products += [
        .library(name: "OctomilMLX", targets: ["OctomilMLX"]),
        .library(name: "OctomilTimeSeries", targets: ["OctomilTimeSeries"]),
    ]
    targets += [
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
}

// MARK: - Package

let package = Package(
    name: "octomil-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)

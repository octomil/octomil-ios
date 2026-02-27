// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Octomil",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Octomil",
            targets: ["Octomil"]
        ),
        .library(
            name: "OctomilClip",
            targets: ["OctomilClip"]
        ),
        .library(
            name: "OctomilMLX",
            targets: ["OctomilMLX"]
        ),
        .library(
            name: "OctomilTimeSeries",
            targets: ["OctomilTimeSeries"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.25.4"),
        .package(url: "https://github.com/kunal732/MLX-Swift-TS", branch: "main"),
    ],
    targets: [
        .target(
            name: "Octomil",
            dependencies: [],
            path: "Sources/Octomil"
        ),
        .target(
            name: "OctomilClip",
            dependencies: ["Octomil"],
            path: "Sources/OctomilClip"
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

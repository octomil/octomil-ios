// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PredictionSample",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "PredictionSample",
            dependencies: [
                .product(name: "OctomilClient", package: "octomil-ios"),
            ]
        ),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TranscriptionSample",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "TranscriptionSample",
            dependencies: [
                .product(name: "OctomilClient", package: "octomil-ios"),
            ]
        ),
    ]
)

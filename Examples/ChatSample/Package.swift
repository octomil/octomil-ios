// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChatSample",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "ChatSample",
            dependencies: [
                .product(name: "OctomilClient", package: "octomil-ios"),
            ]
        ),
    ]
)

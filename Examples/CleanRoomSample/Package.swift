// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanRoomSample",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/octomil/octomil-ios.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CleanRoomSample",
            dependencies: [
                .product(name: "OctomilClient", package: "octomil-ios"),
            ]
        ),
    ]
)

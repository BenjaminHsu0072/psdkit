// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PSDKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "PSDKit", targets: ["PSDKit"]),
    ],
    targets: [
        .target(
            name: "PSDKit",
            path: "Sources/PSDKit"
        ),
        .testTarget(
            name: "PSDKitTests",
            dependencies: ["PSDKit"],
            path: "Tests/PSDKitTests",
            resources: [
                .copy("Fixtures"),
                .copy("Golden"),
            ]
        ),
    ]
)

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
        .executable(name: "PSDKitBenchmark", targets: ["PSDKitBenchmark"]),
    ],
    targets: [
        .target(
            name: "PSDKit",
            path: "Sources/PSDKit"
        ),
        .target(
            name: "PSDKitPerformanceFixtures",
            dependencies: ["PSDKit"],
            path: "Benchmarks/PSDKitPerformanceFixtures"
        ),
        .executableTarget(
            name: "PSDKitBenchmark",
            dependencies: ["PSDKit", "PSDKitPerformanceFixtures"],
            path: "Benchmarks/PSDKitBenchmark"
        ),
        .testTarget(
            name: "PSDKitTests",
            dependencies: ["PSDKit", "PSDKitPerformanceFixtures"],
            path: "Tests/PSDKitTests",
            resources: [
                .copy("Fixtures"),
                .copy("Golden"),
            ]
        ),
    ]
)

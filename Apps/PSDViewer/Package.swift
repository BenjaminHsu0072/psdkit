// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PSDViewer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PSDViewer", targets: ["PSDViewer"]),
    ],
    dependencies: [
        .package(name: "PSDKit", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "PSDViewer",
            dependencies: [
                .product(name: "PSDKit", package: "PSDKit"),
            ]
        ),
    ]
)

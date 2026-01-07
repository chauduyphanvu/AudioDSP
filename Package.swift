// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioDSP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AudioDSP", targets: ["AudioDSP"])
    ],
    targets: [
        .executableTarget(
            name: "AudioDSP",
            path: "AudioDSP",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AudioDSPTests",
            dependencies: ["AudioDSP"],
            path: "Tests"
        )
    ]
)

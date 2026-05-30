// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreAudioManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CoreAudioManager", targets: ["CoreAudioManager"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CoreAudioManager",
            dependencies: []
        ),
        .testTarget(
            name: "CoreAudioManagerTests",
            dependencies: ["CoreAudioManager"]
        )
    ]
)

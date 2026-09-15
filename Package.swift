// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-pet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudePetCore", targets: ["ClaudePetCore"]),
        .executable(name: "ClaudePetApp", targets: ["ClaudePetApp"]),
        .executable(name: "claude-pet", targets: ["claude-pet"]),
    ],
    targets: [
        .target(name: "ClaudePetCore"),
        .executableTarget(name: "ClaudePetApp", dependencies: ["ClaudePetCore"]),
        .executableTarget(name: "claude-pet", dependencies: ["ClaudePetCore"]),
        .testTarget(name: "ClaudePetCoreTests", dependencies: ["ClaudePetCore"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

// 플랫폼별 실행 파일은 파일 단위 `#if os(...)` 로 가른다. SwiftPM 에는 타깃을 플랫폼별로 빼는 방법이
// 없어서, ClaudePetApp(AppKit)은 macOS 밖에서 빈 진입점만 남기고 ClaudePetWin(Win32)은 Windows 밖에서
// 빈 진입점만 남긴다. 그래서 어느 OS 에서든 `swift build` 가 전 타깃을 그대로 돈다.
let package = Package(
    name: "claude-pet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudePetCore", targets: ["ClaudePetCore"]),
        .executable(name: "ClaudePetApp", targets: ["ClaudePetApp"]),
        .executable(name: "ClaudePetWin", targets: ["ClaudePetWin"]),
        .executable(name: "claude-pet", targets: ["claude-pet"]),
    ],
    targets: [
        .target(name: "ClaudePetCore"),
        .executableTarget(name: "ClaudePetApp", dependencies: ["ClaudePetCore"]),
        .executableTarget(name: "ClaudePetWin", dependencies: ["ClaudePetCore"]),
        .executableTarget(name: "claude-pet", dependencies: ["ClaudePetCore"]),
        .testTarget(name: "ClaudePetCoreTests", dependencies: ["ClaudePetCore"]),
    ]
)

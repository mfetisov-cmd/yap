// swift-tools-version: 6.2
import PackageDescription

// Yap = a fixed launcher app (macOS keeps its microphone and Accessibility permissions)
// plus YapCore, a library with the whole app that every rebuild replaces.
let package = Package(
    name: "Yap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YapCore", type: .dynamic, targets: ["YapCore"]),
        .executable(name: "Yap", targets: ["Yap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.2", traits: [])
    ],
    targets: [
        .target(
            name: "YapCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/YapCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Yap",
            path: "Sources/Yap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

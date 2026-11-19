// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Scratchbar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScratchbarCore"),
        .executableTarget(name: "Scratchbar", dependencies: ["ScratchbarCore"]),
        .testTarget(name: "ScratchbarCoreTests", dependencies: ["ScratchbarCore"]),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NowDock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NowDock", targets: ["NowDock"])
    ],
    targets: [
        .target(name: "NowDockCore"),
        .executableTarget(
            name: "NowDock",
            dependencies: ["NowDockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "NowDockCoreTests", dependencies: ["NowDockCore"]),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacVulture",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mac-vulture", targets: ["MacVulture"]),
        .library(name: "MacVultureCore", targets: ["MacVultureCore"])
    ],
    targets: [
        .executableTarget(
            name: "MacVulture",
            dependencies: ["MacVultureCore"],
            path: "App",
            resources: [.copy("Assets.xcassets")]
        ),
        .target(
            name: "MacVultureCore",
            path: "Core",
            resources: [.copy("Resources/path_catalog.json")]
        ),
        .testTarget(
            name: "MacVultureCoreTests",
            dependencies: ["MacVultureCore"],
            path: "Tests/CoreTests"
        )
    ]
)

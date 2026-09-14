// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Limites",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Limites", path: "Sources/Limites"),
        .executableTarget(name: "limites-signal", path: "Sources/limites-signal"),
        .testTarget(name: "LimitesTests", dependencies: ["Limites"], path: "Tests/LimitesTests"),
    ]
)

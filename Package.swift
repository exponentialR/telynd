// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Telynd",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Telynd", targets: ["Telynd"]), .library(name: "TelyndCore", targets: ["TelyndCore"])],
    targets: [
        .target(name: "TelyndCore"),
        .executableTarget(name: "Telynd", dependencies: ["TelyndCore"]),
        .testTarget(name: "TelyndCoreTests", dependencies: ["TelyndCore"], path: "tests/TelyndCoreTests")
    ]
)

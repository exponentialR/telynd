// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Telynd",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Telynd", targets: ["Telynd"]), .library(name: "TelyndCore", targets: ["TelyndCore"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
    targets: [
        .target(name: "TelyndCore"),
        .executableTarget(name: "Telynd", dependencies: ["TelyndCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "TelyndCoreTests", dependencies: ["TelyndCore"], path: "tests/TelyndCoreTests"),
        .testTarget(name: "TelyndAppTests", dependencies: ["Telynd", "TelyndCore"], path: "tests/TelyndAppTests")
    ]
)

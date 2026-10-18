// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DatenblickCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DatenblickCore", targets: ["DatenblickCore"])],
    targets: [
        .target(name: "DatenblickCore", path: "Shared"),
        .testTarget(name: "DatenblickCoreTests", dependencies: ["DatenblickCore"], path: "Tests")
    ]
)

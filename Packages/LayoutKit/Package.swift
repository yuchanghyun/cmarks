// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LayoutKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LayoutKit", targets: ["LayoutKit"]),
    ],
    targets: [
        .target(name: "LayoutKit"),
        .testTarget(name: "LayoutKitTests", dependencies: ["LayoutKit"]),
    ]
)

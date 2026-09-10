// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FileKit", targets: ["FileKit"]),
    ],
    targets: [
        .target(name: "FileKit"),
        .testTarget(name: "FileKitTests", dependencies: ["FileKit"]),
    ]
)

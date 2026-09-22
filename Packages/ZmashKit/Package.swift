// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZmashKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ZmashKit", targets: ["ZmashKit"]),
    ],
    targets: [
        .target(name: "ZmashKit"),
        .testTarget(name: "ZmashKitTests", dependencies: ["ZmashKit"]),
    ]
)

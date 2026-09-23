// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZmashKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ZmashKit", targets: ["ZmashKit"]),
        .executable(name: "race-catalog", targets: ["race-catalog"]),
    ],
    targets: [
        .target(name: "ZmashKit"),
        // Turns gpx/ into the bundled race catalog (`make races`).
        .executableTarget(name: "race-catalog", dependencies: ["ZmashKit"]),
        .testTarget(name: "ZmashKitTests", dependencies: ["ZmashKit"]),
    ]
)

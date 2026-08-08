// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QRPostCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QRPostCore", targets: ["QRPostCore"])
    ],
    targets: [
        .target(name: "QRPostCore"),
        .testTarget(name: "QRPostCoreTests", dependencies: ["QRPostCore"])
    ]
)

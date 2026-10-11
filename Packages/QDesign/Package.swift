// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QDesign",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QDesign", targets: ["QDesign"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "QDesign", dependencies: []),
        .testTarget(name: "QDesignTests", dependencies: ["QDesign"]),
    ]
)

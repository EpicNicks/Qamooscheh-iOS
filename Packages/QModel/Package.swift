// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QModel",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QModel", targets: ["QModel"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "QModel", dependencies: []),
        .testTarget(name: "QModelTests", dependencies: ["QModel"]),
    ]
)

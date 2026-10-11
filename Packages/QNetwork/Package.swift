// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QNetwork",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QNetwork", targets: ["QNetwork"]),
    ],
    dependencies: [
        .package(path: "../QModel"),
    ],
    targets: [
        .target(name: "QNetwork", dependencies: ["QModel"]),
        .testTarget(name: "QNetworkTests", dependencies: ["QNetwork", "QModel"]),
    ]
)

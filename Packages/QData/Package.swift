// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QData", targets: ["QData"]),
    ],
    dependencies: [
        .package(path: "../QModel"),
        .package(path: "../QNetwork"),
    ],
    targets: [
        .target(name: "QData", dependencies: ["QModel", "QNetwork"]),
        .testTarget(name: "QDataTests", dependencies: ["QData"]),
    ]
)

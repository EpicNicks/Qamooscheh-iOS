// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QGrader",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QGrader", targets: ["QGrader"]),
    ],
    dependencies: [
        .package(path: "../QModel"),
    ],
    targets: [
        .target(name: "QGrader", dependencies: ["QModel"]),
        .testTarget(name: "QGraderTests", dependencies: ["QGrader"]),
    ]
)

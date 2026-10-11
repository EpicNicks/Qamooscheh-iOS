// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QFeatures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QFeatures", targets: ["QFeatures"]),
    ],
    dependencies: [
        .package(path: "../QModel"),
        .package(path: "../QDomain"),
        .package(path: "../QNetwork"),
        .package(path: "../QData"),
        .package(path: "../QGrader"),
        .package(path: "../QDesign"),
        .package(path: "../QKeyboard"),
    ],
    targets: [
        .target(name: "QFeatures", dependencies: ["QModel", "QDomain", "QNetwork", "QData", "QGrader", "QDesign", "QKeyboard"]),
        .testTarget(name: "QFeaturesTests", dependencies: ["QFeatures"]),
    ]
)

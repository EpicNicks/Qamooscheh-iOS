// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QKeyboard",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QKeyboard", targets: ["QKeyboard"]),
    ],
    dependencies: [
        .package(path: "../QDomain"),
    ],
    targets: [
        .target(name: "QKeyboard", dependencies: ["QDomain"]),
        .testTarget(name: "QKeyboardTests", dependencies: ["QKeyboard"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QKeyboard",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QKeyboard", targets: ["QKeyboard"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "QKeyboard", dependencies: []),
        .testTarget(name: "QKeyboardTests", dependencies: ["QKeyboard"]),
    ]
)

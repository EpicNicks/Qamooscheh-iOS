// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QDomain", targets: ["QDomain"]),
    ],
    dependencies: [
        .package(path: "../QModel"),
    ],
    targets: [
        .target(name: "QDomain", dependencies: ["QModel"], resources: [.process("Resources")]),
        .testTarget(name: "QDomainTests", dependencies: ["QDomain"]),
    ]
)

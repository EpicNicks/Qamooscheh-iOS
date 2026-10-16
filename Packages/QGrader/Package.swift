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
        .target(
            name: "QGraderWebKit",
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .target(
            name: "QGrader",
            dependencies: ["QModel", "QGraderWebKit"],
            resources: [
                .copy("Resources/grader"),
                .copy("Resources/grader-host.js"),
            ]
        ),
        .testTarget(
            name: "QGraderTests",
            dependencies: ["QGrader"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

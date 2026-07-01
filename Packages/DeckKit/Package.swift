// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DeckKit", targets: ["DeckKit"]),
    ],
    dependencies: [
        .package(path: "../OPSDesignKit"),
    ],
    targets: [
        .target(
            name: "DeckKit",
            dependencies: ["OPSDesignKit"],
            path: "Sources/DeckKit"
        ),
        .testTarget(
            name: "DeckKitTests",
            dependencies: ["DeckKit"],
            path: "Tests/DeckKitTests",
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)

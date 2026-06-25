// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OPSDesignKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OPSDesignKit", targets: ["OPSDesignKit"]),
    ],
    targets: [
        .target(
            name: "OPSDesignKit",
            path: ".",
            sources: [
                "Sources/OPSDesignKit",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OPSDesignKitTests",
            dependencies: ["OPSDesignKit"]
        ),
    ]
)

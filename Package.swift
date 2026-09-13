// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ProducerUpToDate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ProducerUpToDateCore",
            targets: ["ProducerUpToDateCore"]
        ),
        .executable(
            name: "ProducerUpToDate",
            targets: ["ProducerUpToDateApp"]
        )
    ],
    targets: [
        .target(
            name: "ProducerUpToDateCore"
        ),
        .executableTarget(
            name: "ProducerUpToDateApp",
            dependencies: ["ProducerUpToDateCore"]
        ),
        .testTarget(
            name: "ProducerUpToDateCoreTests",
            dependencies: ["ProducerUpToDateCore"]
        )
    ]
)

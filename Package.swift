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
            dependencies: ["ProducerUpToDateCore"],
            exclude: ["OfficialUpdatesView.swift"]
        ),
        .executableTarget(name: "OfficialUpdateProbe", dependencies: ["ProducerUpToDateCore", "OfficialUpdateSupport", "UpdateEnginePrototypeSupport"]),
        .testTarget(name: "OfficialUpdateTests", dependencies: ["ProducerUpToDateCore", "OfficialUpdateSupport"]),
        .target(name: "OfficialUpdateSupport", dependencies: ["ProducerUpToDateCore", "UpdateEnginePrototypeSupport"], resources: [.process("Resources")]),
        .target(name: "UpdateEnginePrototypeSupport", dependencies: ["ProducerUpToDateCore"]),
        .executableTarget(name: "UpdateEnginePrototype", dependencies: ["ProducerUpToDateCore", "UpdateEnginePrototypeSupport"]),
        .testTarget(name: "UpdateEnginePrototypeTests", dependencies: ["ProducerUpToDateCore", "UpdateEnginePrototypeSupport"]),
        .target(name: "MaintainerCatalogueSupport", dependencies: ["ProducerUpToDateCore"]),
        .executableTarget(name: "CatalogueTool", dependencies: ["ProducerUpToDateCore", "MaintainerCatalogueSupport"]),
        .testTarget(
            name: "ProducerUpToDateCoreTests",
            dependencies: ["ProducerUpToDateCore", "MaintainerCatalogueSupport"]
        )
    ]
)

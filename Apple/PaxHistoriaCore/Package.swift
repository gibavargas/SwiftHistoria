// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaxHistoriaCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "PaxHistoriaModels", targets: ["PaxHistoriaModels"]),
        .library(name: "PaxHistoriaEngine", targets: ["PaxHistoriaEngine"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PaxHistoriaModels",
            dependencies: []
        ),
        .target(
            name: "PaxHistoriaEngine",
            dependencies: ["PaxHistoriaModels"]
        )
    ]
)

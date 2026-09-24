// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Alto",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AltoCore", targets: ["AltoCore"]),
        .library(name: "AltoChatterbox", targets: ["AltoChatterbox"]),
        .library(name: "AltoUI", targets: ["AltoUI"]),
        .executable(name: "Alto", targets: ["Alto"]),
        .executable(name: "AltoSpeechWorker", targets: ["AltoSpeechWorker"])
    ],
    dependencies: [
        .package(url: "https://github.com/mlalma/kokoro-ios", revision: "4d6d1d8ff8cd012014180c9cd4cf0151e7682354"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2")
    ],
    targets: [
        .target(name: "AltoCore"),
        .target(name: "AltoChatterbox", dependencies: ["AltoCore"]),
        .target(name: "AltoUI", dependencies: ["AltoCore"]),
        .executableTarget(name: "Alto", dependencies: ["AltoUI"]),
        .executableTarget(name: "AltoSpeechWorker", dependencies: [
            "AltoCore", "AltoChatterbox", .product(name: "KokoroSwift", package: "kokoro-ios"),
            .product(name: "MLX", package: "mlx-swift")
        ]),
        .testTarget(name: "AltoCoreTests", dependencies: ["AltoCore"]),
        .testTarget(name: "AltoChatterboxTests", dependencies: ["AltoChatterbox"]),
        .testTarget(name: "AltoUITests", dependencies: ["AltoUI", "AltoCore"])
    ],
    swiftLanguageModes: [.v5]
)

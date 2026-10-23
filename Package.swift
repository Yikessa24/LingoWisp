// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LingoWispCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LingoWispCore", targets: ["LingoWispCore"])],
    targets: [
        .target(name: "LingoWispCore", path: "LingoWisp", exclude: ["App/LingoWispApp.swift", "Resources"]),
        .testTarget(name: "LingoWispCoreTests", dependencies: ["LingoWispCore"], path: "Tests/LingoWispCoreTests")
    ]
)

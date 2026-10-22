// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HoldTranslateCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "HoldTranslateCore", targets: ["HoldTranslateCore"])],
    targets: [
        .target(name: "HoldTranslateCore", path: "HoldTranslate/Core"),
        .testTarget(name: "HoldTranslateCoreTests", dependencies: ["HoldTranslateCore"], path: "Tests/HoldTranslateCoreTests")
    ]
)

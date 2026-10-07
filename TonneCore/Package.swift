// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TonneCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "TonneCore", targets: ["TonneCore"]),
    ],
    targets: [
        .target(name: "TonneCore"),
        .testTarget(name: "TonneCoreTests", dependencies: ["TonneCore"]),
    ],
    swiftLanguageVersions: [.v5]
)

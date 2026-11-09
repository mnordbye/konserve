// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SMBConnectorCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SMBConnectorCore", targets: ["SMBConnectorCore"])
    ],
    targets: [
        .target(name: "SMBConnectorCore", linkerSettings: [.linkedFramework("NetFS")]),
        .testTarget(name: "SMBConnectorCoreTests", dependencies: ["SMBConnectorCore"])
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KonserveCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KonserveCore", targets: ["KonserveCore"])
    ],
    targets: [
        .target(name: "KonserveCore", linkerSettings: [.linkedFramework("NetFS")]),
        .testTarget(name: "KonserveCoreTests", dependencies: ["KonserveCore"])
    ]
)

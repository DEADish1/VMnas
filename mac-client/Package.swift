// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VMnasAdmin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VMnasAdmin", targets: ["VMnasAdmin"])
    ],
    targets: [
        .executableTarget(name: "VMnasAdmin")
    ]
)

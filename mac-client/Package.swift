// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CamoNASAdmin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CamoNASAdmin", targets: ["CamoNASAdmin"])
    ],
    targets: [
        .executableTarget(name: "CamoNASAdmin")
    ]
)

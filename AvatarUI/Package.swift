// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AvatarUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AvatarUI", targets: ["AvatarUI"])
    ],
    targets: [
        // E20.1: Phosphor-package geblokkeerd in de CLI-DoD (zie DSIcon /
        // DECISIONS-PENDING). DSIcon draait interim op SF Symbols.
        .target(name: "AvatarUI"),
        .testTarget(name: "AvatarUITests", dependencies: ["AvatarUI"])
    ]
)

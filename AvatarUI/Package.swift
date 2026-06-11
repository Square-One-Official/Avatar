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
        .target(name: "AvatarUI"),
        .testTarget(name: "AvatarUITests", dependencies: ["AvatarUI"])
    ]
)

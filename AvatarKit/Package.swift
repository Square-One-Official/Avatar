// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AvatarKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AvatarKit", targets: ["AvatarKit"])
    ],
    targets: [
        .target(name: "AvatarKit"),
        .testTarget(name: "AvatarKitTests", dependencies: ["AvatarKit"])
    ]
)

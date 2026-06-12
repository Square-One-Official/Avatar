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
    dependencies: [
        // Zip-extractie voor het ORMBG-modelpakket (zelfde versie als
        // project.yml gebruikt voor de v1-app).
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20")
    ],
    targets: [
        .target(name: "AvatarKit", dependencies: [
            .product(name: "ZIPFoundation", package: "ZIPFoundation")
        ]),
        .testTarget(name: "AvatarKitTests", dependencies: ["AvatarKit"])
    ]
)

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
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        // Auth 2.0 (e-mail + OTP) — zelfde major als de v1-app.
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
    ],
    targets: [
        .target(name: "AvatarKit", dependencies: [
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "Supabase", package: "supabase-swift"),
            .product(name: "Auth", package: "supabase-swift")
        ]),
        .testTarget(name: "AvatarKitTests", dependencies: ["AvatarKit"])
    ]
)

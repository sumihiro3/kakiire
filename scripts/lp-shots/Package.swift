// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gen",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "Kakiire", path: "../..")],
    targets: [
        .executableTarget(
            name: "gen",
            dependencies: [
                .product(name: "KakiireCore", package: "Kakiire"),
                .product(name: "KakiireIO", package: "Kakiire"),
            ]
        ),
    ]
)

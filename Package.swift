// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kakiire",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KakiireCore", targets: ["KakiireCore"]),
        .library(name: "KakiireIO", targets: ["KakiireIO"]),
    ],
    targets: [
        .target(name: "KakiireCore"),
        .target(name: "KakiireIO", dependencies: ["KakiireCore"]),
        .testTarget(
            name: "KakiireCoreTests",
            dependencies: ["KakiireCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "KakiireIOTests", dependencies: ["KakiireIO"]),
    ]
)

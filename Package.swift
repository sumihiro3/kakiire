// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kakiire",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KakiireCore", targets: ["KakiireCore"]),
        .library(name: "KakiireIO", targets: ["KakiireIO"]),
        .executable(name: "kakiire", targets: ["kakiire"]),
    ],
    targets: [
        .target(name: "KakiireCore"),
        .target(name: "KakiireIO", dependencies: ["KakiireCore"]),
        // CLI と MCP サーバー(ADR 0007)。処理はライブラリに置き、実行ファイルは入出力をつなぐだけ。
        .target(name: "KakiireTooling", dependencies: ["KakiireCore", "KakiireIO"]),
        .executableTarget(name: "kakiire", dependencies: ["KakiireTooling"]),
        .testTarget(
            name: "KakiireCoreTests",
            dependencies: ["KakiireCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "KakiireIOTests", dependencies: ["KakiireIO"]),
        .testTarget(name: "KakiireToolingTests", dependencies: ["KakiireTooling"]),
    ]
)

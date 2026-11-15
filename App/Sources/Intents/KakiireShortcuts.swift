import AppIntents

/// Spotlight と Siri に出すショートカット。フレーズの訳は `AppShortcuts.xcstrings`。
struct KakiireShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureScreenshotIntent(),
            phrases: [
                "\(.applicationName) でスクリーンショットを撮る",
                "\(.applicationName) で範囲を撮る",
            ],
            shortTitle: "範囲を撮る",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: CurrentImageIntent(),
            phrases: ["\(.applicationName) で編集中の画像を取得"],
            shortTitle: "編集中の画像",
            systemImageName: "photo"
        )
    }
}

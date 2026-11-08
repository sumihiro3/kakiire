import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        NSApp.windowsMenu = NSApp.mainMenu?.item(withTitle: "ウインドウ")?.submenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder から画像を渡されて起動したときは、その文書が開くので歓迎画面は出さない。
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty { WelcomeWindowController.shared.show() }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindowController.shared.show() }
        return true
    }

    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.show() }

    /// 編集ウインドウがないときの ⌘V と「クリップボードから新規」。
    @objc func paste(_ sender: Any?) { newFromClipboard(sender) }

    @objc func newFromClipboard(_ sender: Any?) {
        if !KakiireDocumentController.current.openFromPasteboard(.general) { NSSound.beep() }
    }

    /// 範囲を選んでスクリーンショットを撮り、新しいウインドウで開く。
    @objc func newFromScreenshot(_ sender: Any?) {
        ScreenCapture.interactive { asset in
            guard let asset else { return }
            KakiireDocumentController.current.openNew(asset: asset, name: "スクリーンショット")
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(paste(_:)), #selector(newFromClipboard(_:)):
            PasteboardImage.hasImage(.general)
        default:
            true
        }
    }
}

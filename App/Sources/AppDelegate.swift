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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let pending = NSDocumentController.shared.documents.compactMap { $0 as? KakiireDocument }.filter(\.hasUnexportedChanges)
        guard !pending.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "書き出していない変更があります"
        alert.informativeText = "\(pending.count) 件の画像の変更は保存されません。終了しますか？"
        alert.addButton(withTitle: "終了")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// 編集ウインドウがないときの ⌘V と「クリップボードから新規」。
    @objc func paste(_ sender: Any?) { newFromClipboard(sender) }

    @objc func newFromClipboard(_ sender: Any?) {
        if !KakiireDocumentController.current.openFromPasteboard(.general) { NSSound.beep() }
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

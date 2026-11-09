import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        NSApp.windowsMenu = NSApp.mainMenu?.item(withTitle: String(localized: "ウインドウ"))?.submenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPreferences()
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
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

    /// ウインドウを全部閉じても終了しない(メニューバーとショートカットから撮れるように)。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 撮影のショートカットとメニューバーのアイコンを設定に合わせる。
    private func applyPreferences() {
        if !HotKey.shared.register(Preferences.captureShortcut, action: { [weak self] in self?.newFromScreenshot(nil) }) {
            NSLog("Kakiire: could not register capture shortcut %@ (another app may use it)", Preferences.captureShortcut.rawValue)
        }
        if Preferences.showsStatusItem, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "Kakiire")
            item.menu = Self.statusMenu()
            statusItem = item
        } else if !Preferences.showsStatusItem, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private static func statusMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: String(localized: "スクリーンショットを撮る"), action: #selector(newFromScreenshot(_:)), keyEquivalent: "")
        m.addItem(withTitle: String(localized: "クリップボードから新規"), action: #selector(newFromClipboard(_:)), keyEquivalent: "")
        m.addItem(withTitle: String(localized: "開く…"), action: #selector(openFromStatusItem(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: String(localized: "設定…"), action: #selector(showSettings(_:)), keyEquivalent: "")
        m.addItem(withTitle: String(localized: "Kakiire を終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return m
    }

    /// メニューバーから開くときは、開くパネルが他のアプリの後ろに出ないよう先に前面にする。
    @objc func openFromStatusItem(_ sender: Any?) {
        NSApp.activate()
        NSDocumentController.shared.openDocument(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        NSApp.activate()
        SettingsWindowController.shared.show()
    }

    /// 編集ウインドウがないときの ⌘V と「クリップボードから新規」。
    @objc func paste(_ sender: Any?) { newFromClipboard(sender) }

    @objc func newFromClipboard(_ sender: Any?) {
        if !KakiireDocumentController.current.openFromPasteboard(.general) { NSSound.beep() }
    }

    /// 範囲を選んでスクリーンショットを撮り、新しいウインドウで開く。
    @objc func newFromScreenshot(_ sender: Any?) {
        ScreenCapture.interactive { asset in
            guard let asset else { return }
            KakiireDocumentController.current.openNew(asset: asset, name: String(localized: "スクリーンショット"))
        }
    }

    func application(_ application: NSApplication, willPresentError error: any Error) -> any Error {
        ErrorLocalizer.localize(error)
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

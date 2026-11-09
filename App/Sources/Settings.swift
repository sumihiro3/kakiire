import AppKit

/// 編集ツールバーの置き場所。
enum ToolbarPosition: String, CaseIterable {
    case left, top

    var title: String { self == .left ? String(localized: "ウインドウの左") : String(localized: "ウインドウの上") }
}

/// アプリの設定(UserDefaults)。変わったら `didChange` を流し、開いているウインドウにすぐ反映する。
enum Preferences {
    static let didChange = Notification.Name("KakiirePreferencesDidChange")
    private static let toolbarPositionKey = "toolbarPosition"
    private static let showsLayerPanelKey = "showsLayerPanel"

    /// レイヤーパネル(ウインドウ右)を出すか。既定は出す。
    static var showsLayerPanel: Bool {
        get { UserDefaults.standard.object(forKey: showsLayerPanelKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: showsLayerPanelKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    private static let captureShortcutKey = "captureShortcut"
    private static let showsStatusItemKey = "showsStatusItem"

    /// 撮影のグローバルショートカット。既定は ⌃⇧⌘5。
    static var captureShortcut: CaptureShortcut {
        get { UserDefaults.standard.string(forKey: captureShortcutKey).flatMap(CaptureShortcut.init) ?? .controlShiftCommand5 }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: captureShortcutKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// メニューバーに Kakiire のアイコンを出すか。既定は出す。
    static var showsStatusItem: Bool {
        get { UserDefaults.standard.object(forKey: showsStatusItemKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: showsStatusItemKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var toolbarPosition: ToolbarPosition {
        get { UserDefaults.standard.string(forKey: toolbarPositionKey).flatMap(ToolbarPosition.init) ?? .left }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: toolbarPositionKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// 「設定…」(⌘,)のウインドウ。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private let positionPopup = NSPopUpButton()
    private let shortcutPopup = NSPopUpButton()
    private let statusItemCheck = NSButton(checkboxWithTitle: String(localized: "メニューバーに表示する"), target: nil, action: nil)

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "設定")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        positionPopup.addItems(withTitles: ToolbarPosition.allCases.map(\.title))
        positionPopup.target = self
        positionPopup.action = #selector(positionChanged)

        shortcutPopup.addItems(withTitles: CaptureShortcut.allCases.map(\.title))
        shortcutPopup.target = self
        shortcutPopup.action = #selector(shortcutChanged)
        shortcutPopup.toolTip = String(localized: "ほかのアプリを使っているときも、このキーで範囲を選んで撮れる")
        statusItemCheck.target = self
        statusItemCheck.action = #selector(statusItemChanged)

        let label = NSTextField(labelWithString: String(localized: "編集ツールバー:"))
        let grid = NSGridView(views: [
            [label, positionPopup],
            [NSTextField(labelWithString: String(localized: "撮影のショートカット:")), shortcutPopup],
            [NSTextField(labelWithString: String(localized: "メニューバー:")), statusItemCheck],
        ])
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        positionPopup.selectItem(at: ToolbarPosition.allCases.firstIndex(of: Preferences.toolbarPosition) ?? 0)
        shortcutPopup.selectItem(at: CaptureShortcut.allCases.firstIndex(of: Preferences.captureShortcut) ?? 0)
        statusItemCheck.state = Preferences.showsStatusItem ? .on : .off
        window?.center()
        showWindow(nil)
    }

    @objc private func shortcutChanged() {
        Preferences.captureShortcut = CaptureShortcut.allCases[shortcutPopup.indexOfSelectedItem]
    }

    @objc private func statusItemChanged() {
        Preferences.showsStatusItem = statusItemCheck.state == .on
    }

    @objc private func positionChanged() {
        Preferences.toolbarPosition = ToolbarPosition.allCases[positionPopup.indexOfSelectedItem]
    }
}

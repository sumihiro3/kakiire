import AppKit

/// 編集ツールバーの置き場所。
enum ToolbarPosition: String, CaseIterable {
    case left, top

    var title: String { self == .left ? "ウインドウの左" : "ウインドウの上" }
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

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "設定"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        positionPopup.addItems(withTitles: ToolbarPosition.allCases.map(\.title))
        positionPopup.target = self
        positionPopup.action = #selector(positionChanged)

        let label = NSTextField(labelWithString: "編集ツールバー:")
        let grid = NSGridView(views: [[label, positionPopup]])
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
        window?.center()
        showWindow(nil)
    }

    @objc private func positionChanged() {
        Preferences.toolbarPosition = ToolbarPosition.allCases[positionPopup.indexOfSelectedItem]
    }
}

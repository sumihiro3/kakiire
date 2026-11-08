import AppKit
import KakiireIO

/// 文書が1つもないときに出す、空の編集画面。画像はドロップ・撮影・クリップボード・ファイルから取り込む。
///
/// 文書に「画像なし」の状態は作らない。取り込んだら同じ位置・大きさで編集ウインドウを開き、これは閉じる。
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Kakiire"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        super.init(window: window)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: Preferences.didChange, object: nil)
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 表示中ならその枠。編集ウインドウが引き継ぐ。
    var visibleFrame: NSRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
    }

    func closeIfOpen() { window?.orderOut(nil) }

    /// ツールバーの位置の設定に合わせて組み直す。
    @objc private func rebuild() {
        let root = NSView()
        let position = Preferences.toolbarPosition
        let bar = ToolBarView(controller: nil, position: position)
        bar.update(tool: .select, style: DrawingStyle(), target: .stroke, dashEnabled: false, enabled: false)
        let drop = DropTargetView()
        for v in [bar, drop] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        var cs: [NSLayoutConstraint] = [
            drop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            drop.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.topAnchor.constraint(equalTo: root.topAnchor),
        ]
        if position == .left {
            cs += [bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                   drop.topAnchor.constraint(equalTo: root.topAnchor),
                   drop.leadingAnchor.constraint(equalTo: bar.trailingAnchor)]
        } else {
            cs += [bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                   drop.topAnchor.constraint(equalTo: bar.bottomAnchor),
                   drop.leadingAnchor.constraint(equalTo: root.leadingAnchor)]
        }
        NSLayoutConstraint.activate(cs)
        window?.contentView = root
    }
}

/// 画像ファイル・画像データのドロップを受けて新しい文書を開く。取り込み方のボタンも置く。
final class DropTargetView: NSView {
    private var highlighted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + PasteboardImage.dataTypes)

        let icon = NSImageView(image: NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 44, weight: .light)
        icon.contentTintColor = .tertiaryLabelColor
        let label = NSTextField(labelWithString: "画像をここにドロップ")
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .secondaryLabelColor

        let buttons = NSStackView(views: [
            Self.button("スクリーンショットを撮る", "camera.viewfinder", #selector(AppDelegate.newFromScreenshot(_:)),
                        tip: "範囲を選んで撮る。Space でウインドウ単位、Esc で取り消し(⌃⇧⌘N)"),
            Self.button("クリップボードから", "doc.on.clipboard", #selector(AppDelegate.newFromClipboard(_:)),
                        tip: "コピーした画像を開く(⌘V)"),
            Self.button("ファイルを開く…", "folder", #selector(NSDocumentController.openDocument(_:)),
                        tip: "画像や .kakiire ファイルを開く(⌘O)"),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [icon, label, buttons])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(28, after: label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func button(_ title: String, _ symbol: String, _ action: Selector, tip: String) -> NSButton {
        let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: nil, action: action)
        b.imagePosition = .imageLeading
        b.bezelStyle = .push
        b.controlSize = .large
        b.toolTip = tip
        return b
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        let r = bounds.insetBy(dx: 24, dy: 24)
        let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        path.lineWidth = 2
        path.setLineDash([8, 6], count: 2, phase: 0)
        (highlighted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard PasteboardImage.hasImage(sender.draggingPasteboard) else { return [] }
        highlighted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { highlighted = false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        highlighted = false
        return KakiireDocumentController.current.openFromDrop(sender.draggingPasteboard)
    }
}

extension KakiireDocumentController {
    static var current: KakiireDocumentController {
        // swiftlint:disable:next force_cast
        NSDocumentController.shared as! KakiireDocumentController
    }

    /// ドロップされた画像を開く。ファイルが複数なら全部開く。
    func openFromDrop(_ pb: NSPasteboard) -> Bool {
        let urls = PasteboardImage.imageFileURLs(pb)
        if urls.isEmpty { return openFromPasteboard(pb) }
        for url in urls {
            openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        return true
    }
}

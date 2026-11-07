import AppKit
import KakiireIO

/// 文書が1つもないときに出す、画像の受け口。
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Kakiire"
        window.isReleasedWhenClosed = false
        window.contentView = DropTargetView()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        showWindow(nil)
    }

    func closeIfOpen() { window?.orderOut(nil) }
}

/// 画像ファイル・画像データのドロップを受けて新しい文書を開く。
final class DropTargetView: NSView {
    private var highlighted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + PasteboardImage.dataTypes)

        let label = NSTextField(wrappingLabelWithString: "画像をここにドロップ\n\n⌘V でクリップボードから貼り付け\n⌘O でファイルを開く")
        label.alignment = .center
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 16, dy: 16)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
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

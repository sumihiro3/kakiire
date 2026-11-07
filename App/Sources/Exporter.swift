import AppKit
import KakiireCore
import KakiireIO
import UniformTypeIdentifiers

/// 書き出し・コピー・ドラッグでの持ち出し。どれもモザイク・ぼかしを焼き込んだ画像を出す。
enum Exporter {
    static func copyToPasteboard(_ doc: Document, cache: RenderCache) throws {
        guard let img = Renderer.makeImage(doc, cache: cache) else { throw ImageExportError.renderFailed }
        let png = try ImageExport.data(img, format: .png)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: img).tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
    }

    static func runSavePanel(for kdoc: KakiireDocument, cache: RenderCache, window: NSWindow) {
        let panel = NSSavePanel()
        let options = ExportOptionsView()
        panel.accessoryView = options
        panel.nameFieldStringValue = kdoc.displayName + ".png"
        panel.allowedContentTypes = [.png]
        panel.canSelectHiddenExtension = true
        options.onFormatChange = { [weak panel] f in
            guard let panel else { return }
            panel.allowedContentTypes = [f.utType]
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + f.fileExtension
        }
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            do {
                let data = try ImageExport.data(of: kdoc.content, format: options.format,
                                                jpegQuality: options.jpegQuality, cache: cache)
                try data.write(to: url, options: .atomic)
            } catch {
                kdoc.presentError(error)
            }
        }
    }
}

/// 保存パネルの下に出す、形式と JPEG 品質の選択欄。
final class ExportOptionsView: NSView {
    private let formatPopup = NSPopUpButton()
    private let quality = NSSlider(value: 0.9, minValue: 0.3, maxValue: 1, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: "品質:")
    var onFormatChange: ((ExportFormat) -> Void)?

    var format: ExportFormat { ExportFormat.allCases[max(0, formatPopup.indexOfSelectedItem)] }
    var jpegQuality: Double { quality.doubleValue }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 44))
        formatPopup.addItems(withTitles: ["PNG", "JPEG"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        quality.target = self
        let stack = NSStackView(views: [NSTextField(labelWithString: "形式:"), formatPopup, qualityLabel, quality])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            quality.widthAnchor.constraint(equalToConstant: 140),
        ])
        formatChanged()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func formatChanged() {
        let isJPEG = format == .jpeg
        quality.isHidden = !isJPEG
        qualityLabel.isHidden = !isJPEG
        onFormatChange?(format)
    }
}

/// ドラッグすると、仕上がりの PNG を Finder や他のアプリへ持ち出せるつまみ。
final class DragOutView: NSView, NSDraggingSource {
    weak var controller: EditorWindowController?
    private var writer: PNGPromiseWriter?

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        if let img = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "画像を持ち出す") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let sized = img.withSymbolConfiguration(cfg) ?? img
            let s = sized.size
            sized.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let controller, let kdoc = controller.document as? KakiireDocument,
              let img = Renderer.makeImage(kdoc.content, cache: controller.cache),
              let png = try? ImageExport.data(img, format: .png) else { NSSound.beep(); return }

        let w = PNGPromiseWriter(data: png, fileName: kdoc.displayName + ".png")
        writer = w
        let provider = PNGPromiseProvider(fileType: UTType.png.identifier, delegate: w)
        provider.pngData = png
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSImage(cgImage: img, size: NSSize(width: 96, height: 96 * CGFloat(img.height) / CGFloat(max(img.width, 1))))
        item.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: preview.size), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// ファイルの約束(Finder 向け)に加えて、PNG データ(他アプリへの直接ドロップ向け)も載せる。
nonisolated final class PNGPromiseProvider: NSFilePromiseProvider, @unchecked Sendable {
    var pngData = Data()

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.png]
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .png ? pngData : super.pasteboardPropertyList(forType: type)
    }
}

/// 約束したファイルを書く。AppKit が別スレッドから呼ぶので、値は不変のものだけを持つ。
final class PNGPromiseWriter: NSObject, NSFilePromiseProviderDelegate, Sendable {
    let data: Data
    let fileName: String

    init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping ((any Error)?) -> Void) {
        do {
            try data.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

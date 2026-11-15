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
    private let qualityLabel = NSTextField(labelWithString: String(localized: "品質:"))
    var onFormatChange: ((ExportFormat) -> Void)?

    var format: ExportFormat { ExportFormat.allCases[max(0, formatPopup.indexOfSelectedItem)] }
    var jpegQuality: Double { quality.doubleValue }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 44))
        formatPopup.addItems(withTitles: ["PNG", "JPEG"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        quality.target = self
        let stack = NSStackView(views: [NSTextField(labelWithString: String(localized: "形式:")), formatPopup, qualityLabel, quality])
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
        if let img = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: String(localized: "画像を持ち出す")) {
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

        let fileName = DragOutFiles.fileName(for: kdoc.displayName)
        let w = PNGPromiseWriter(data: png, fileName: fileName)
        writer = w
        let provider = PNGPromiseProvider(fileType: UTType.png.identifier, delegate: w)
        provider.pngData = png
        provider.fileURL = DragOutFiles.write(png, fileName: fileName)
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSImage(cgImage: img, size: NSSize(width: 96, height: 96 * CGFloat(img.height) / CGFloat(max(img.width, 1))))
        item.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: preview.size), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// ファイルの約束(Finder 向け)に加えて、PNG データ(他アプリへの直接ドロップ向け)と、
/// 書き出し済みの実ファイルの URL も載せる。ブラウザーと Electron 系のアプリ(Slack など)は
/// ファイルの約束も生の PNG も受け取らず、実ファイルの URL だけをページに渡すため。
nonisolated final class PNGPromiseProvider: NSFilePromiseProvider, @unchecked Sendable {
    var pngData = Data()
    var fileURL: URL?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.png] + (fileURL == nil ? [] : [.fileURL])
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .png: pngData
        case .fileURL: (fileURL as NSURL?)?.pasteboardPropertyList(forType: .fileURL)
        default: super.pasteboardPropertyList(forType: type)
        }
    }
}

/// ドラッグで持ち出す PNG の一時ファイル。サンドボックスの一時フォルダーに、ドラッグごとのフォルダーを切って置く。
///
/// ドロップ先(ブラウザーなど)はドロップの後でファイルを読むことがあるので、ドラッグの終わりでは消さない。
/// 次のドラッグの開始時に古いものを、起動時にすべてを消す。
enum DragOutFiles {
    private static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DragOut", isDirectory: true)
    }

    /// これより古い一時ファイルは、次のドラッグの開始時に消す。
    private static let maxAge: TimeInterval = 60 * 60

    /// 文書の表示名から、ファイル名に使えない文字を除いた PNG のファイル名を作る。
    static func fileName(for displayName: String) -> String {
        let cleaned = displayName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return (cleaned.isEmpty ? "Kakiire" : cleaned) + ".png"
    }

    /// PNG を一時ファイルに書き、その URL を返す。書けなければ nil(ファイルの約束と PNG データだけで続ける)。
    static func write(_ png: Data, fileName: String) -> URL? {
        removeOld()
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 起動時に呼ぶ。前回までに持ち出した一時ファイルをすべて消す。
    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func removeOld() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-maxAge)
        for dir in dirs {
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < limit { try? fm.removeItem(at: dir) }
        }
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

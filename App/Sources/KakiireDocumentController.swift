import AppKit
import KakiireCore
import KakiireIO

/// 画像ファイルを「無題の新規文書」として開く。
///
/// 画像を NSDocument の Viewer 型で開くと fileURL に元の画像が入り、「保存」で元画像を上書きしてしまう。
/// それを避けるため fileURL を持たない文書を作る。
final class KakiireDocumentController: NSDocumentController {
    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        let asset = try ImageImport.asset(contentsOf: url)
        noteNewRecentDocumentURL(url)
        return KakiireDocument(asset: asset, sourceName: url.deletingPathExtension().lastPathComponent)
    }

    /// 取り込んだ画像で新しいウインドウを開く。
    func openNew(asset: ImageAsset, name: String) {
        let doc = KakiireDocument(asset: asset, sourceName: name)
        addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        WelcomeWindowController.shared.closeIfOpen()
    }

    /// クリップボードの画像(またはコピーした画像ファイル)を開く。画像がなければ false。
    @discardableResult
    func openFromPasteboard(_ pb: NSPasteboard) -> Bool {
        if let url = PasteboardImage.imageFileURLs(pb).first {
            openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
            return true
        }
        guard let asset = PasteboardImage.asset(pb) else { return false }
        openNew(asset: asset, name: "クリップボード")
        return true
    }
}

/// クリップボード・ドラッグ&ドロップから画像を読む。
enum PasteboardImage {
    static let dataTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic"),
    ]

    static func imageFileURLs(_ pb: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ImageImport.readableTypes.map(\.identifier),
        ]
        return pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
    }

    static func asset(_ pb: NSPasteboard) -> ImageAsset? {
        for type in dataTypes {
            if let data = pb.data(forType: type), let asset = try? ImageImport.asset(from: data) { return asset }
        }
        return nil
    }

    static func hasImage(_ pb: NSPasteboard) -> Bool {
        pb.availableType(from: dataTypes) != nil || !imageFileURLs(pb).isEmpty
    }
}

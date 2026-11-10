import Foundation
import ImageIO
import KakiireIO
import QuickLookUI
import UniformTypeIdentifiers

/// スペースキーのプレビュー。保存時に焼き込んだ preview.png をそのまま見せる。
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let png = try KakiireArchive.previewData(Data(contentsOf: request.fileURL, options: .mappedIfSafe))
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw CocoaError(.fileReadCorruptFile) }
        return QLPreviewReply(dataOfContentType: .png, contentSize: CGSize(width: w, height: h)) { _ in png }
    }
}

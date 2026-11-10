import CoreGraphics
import Foundation
import ImageIO
import KakiireIO
import QuickLookThumbnailing

/// Finder のアイコンに、保存時に焼き込んだ preview.png を縮めて出す。
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let png = try KakiireArchive.previewData(Data(contentsOf: request.fileURL, options: .mappedIfSafe))
            guard let src = CGImageSourceCreateWithData(png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
            else { return handler(nil, CocoaError(.fileReadCorruptFile)) }
            let size = Self.fit(CGSize(width: image.width, height: image.height), in: request.maximumSize)
            handler(QLThumbnailReply(contextSize: size) { ctx in
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(origin: .zero, size: size))
                return true
            }, nil)
        } catch {
            handler(nil, error)
        }
    }

    /// 縦横比を保って `box` に収めた大きさ(拡大はしない)。
    static func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let s = min(1, box.width / size.width, box.height / size.height)
        return CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
    }
}

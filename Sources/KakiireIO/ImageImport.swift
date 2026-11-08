import CoreGraphics
import Foundation
import ImageIO
import KakiireCore
import UniformTypeIdentifiers

public enum ImageImportError: Error, LocalizedError {
    case unreadable

    public var errorDescription: String? { "The image could not be read." }
}

/// 画像ファイル・クリップボードのデータから元画像(`ImageAsset`)を作る。
public enum ImageImport {
    /// 取り込めるファイルの種類。
    public static let readableTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .bmp, .image]

    public static func asset(contentsOf url: URL) throws -> ImageAsset {
        try asset(from: Data(contentsOf: url))
    }

    /// エンコード済みの画像データから取り込む。EXIF の向きを反映した正立画像にする。
    /// 向きの補正が要らない PNG は元のバイト列をそのまま保持する(取り込んだときのまま)。
    public static func asset(from data: Data) throws -> ImageAsset {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else {
            throw ImageImportError.unreadable
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let isPNG = (CGImageSourceGetType(src) as String?) == UTType.png.identifier

        if orientation == 1, let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return isPNG ? ImageAsset(cgImage: img, data: data) : try asset(from: img)
        }
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ImageImportError.unreadable
        }
        return try asset(from: img)
    }

    /// 生の画像から取り込む(PNG にエンコードして保持する)。
    public static func asset(from image: CGImage) throws -> ImageAsset {
        ImageAsset(cgImage: image, data: try ImageExport.data(image, format: .png))
    }
}

import CoreGraphics
import Foundation
import ImageIO
import KakiireCore
import UniformTypeIdentifiers

public enum ExportFormat: String, Sendable, CaseIterable {
    case png, jpeg

    public var utType: UTType { self == .png ? .png : .jpeg }
    public var fileExtension: String { self == .png ? "png" : "jpg" }
}

public enum ImageExportError: Error, LocalizedError {
    case renderFailed, encodeFailed

    public var errorDescription: String? {
        switch self {
        case .renderFailed: "The image could not be rendered."
        case .encodeFailed: "The image could not be encoded."
        }
    }
}

/// 書き出し(PNG / JPEG)。モザイク・ぼかしは必ず焼き込まれ、メタデータは付けない。
public enum ImageExport {
    /// 文書を描画してエンコードする。
    public static func data(of doc: Document, format: ExportFormat, jpegQuality: Double = 0.9,
                            cache: RenderCache = RenderCache()) throws -> Data {
        guard let img = Renderer.makeImage(doc, cache: cache) else { throw ImageExportError.renderFailed }
        return try data(img, format: format, jpegQuality: jpegQuality)
    }

    /// `.kakiire` のデータを画像にする。`scale` を渡すと、文書に保存された書き出しの倍率を置き換える
    /// (MCP の export と同じ)。新しすぎる形式で編集できない文書も書き出せる。
    public static func data(ofArchive archive: Data, format: ExportFormat, scale: Double? = nil,
                            jpegQuality: Double = 0.9) throws -> Data {
        var doc = try KakiireArchive.read(archive).document
        if let scale { doc = doc.applying([.setOutputScale(scale)]) }
        return try data(of: doc, format: format, jpegQuality: jpegQuality)
    }

    public static func data(_ image: CGImage, format: ExportFormat, jpegQuality: Double = 0.9) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.utType.identifier as CFString, 1, nil) else {
            throw ImageExportError.encodeFailed
        }
        var props: [CFString: Any] = [:]
        var img = image
        if format == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = clamp(jpegQuality, 0, 1)
            img = flattenedOnWhite(image)
        }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageExportError.encodeFailed }
        return format == .png ? stripPNGMetadata(out as Data) : stripJPEGMetadata(out as Data)
    }

    /// JPEG で残す APP セグメント:JFIF(APP0)・ICC プロファイル(APP2)・Adobe の色変換(APP14)。
    static let keptJPEGAppMarkers: Set<UInt8> = [0xE0, 0xE2, 0xEE]

    /// ImageIO が付ける Exif(APP1)・Photoshop の情報(APP13)・コメントを取り除く。
    /// 画像データ(SOS 以降)には触れない。形式が崩れていれば元のデータを返す。
    static func stripJPEGMetadata(_ jpg: Data) -> Data {
        let b = [UInt8](jpg)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return jpg }
        var out = Data(b[0..<2])
        var i = 2
        while i + 4 <= b.count {
            guard b[i] == 0xFF else { return jpg }
            let marker = b[i + 1]
            if marker == 0xDA {
                out.append(contentsOf: b[i...])
                return out
            }
            let end = i + 2 + (Int(b[i + 2]) << 8 | Int(b[i + 3]))
            guard end <= b.count else { return jpg }
            let isApp = (0xE0...0xEF).contains(marker)
            let drop = marker == 0xFE || (isApp && !keptJPEGAppMarkers.contains(marker))
            if !drop { out.append(contentsOf: b[i..<end]) }
            i = end
        }
        return jpg
    }

    /// 描画に必要なチャンク(と色の解釈に要るもの)だけを残す。
    static let keptPNGChunks: Set<String> = ["IHDR", "PLTE", "tRNS", "IDAT", "IEND", "iCCP", "sRGB", "cHRM", "gAMA", "pHYs"]

    /// ImageIO が付ける eXIf などのメタデータチャンクを取り除く。チャンクごとに CRC が独立しているので、
    /// 丸ごと抜いても残りはそのまま有効。形式が崩れていれば元のデータを返す。
    static func stripPNGMetadata(_ png: Data) -> Data {
        let b = [UInt8](png)
        guard b.count > 8 else { return png }
        var out = Data(b[0..<8])
        var i = 8
        while i + 12 <= b.count {
            let len = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            let end = i + 12 + len
            guard end <= b.count, let type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) else { return png }
            if keptPNGChunks.contains(type) { out.append(contentsOf: b[i..<end]) }
            i = end
        }
        return out
    }

    /// JPEG は透明を持てないので白地に合成する。
    static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let ctx = Renderer.makeContext(width: image.width, height: image.height,
                                             colorSpace: Renderer.colorSpace(for: image)) else { return image }
        let r = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(r)
        Renderer.drawImage(image, in: r, ctx)
        return ctx.makeImage() ?? image
    }
}

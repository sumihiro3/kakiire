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
        case .renderFailed: "画像を描画できませんでした。"
        case .encodeFailed: "画像を書き出せませんでした。"
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
        return format == .png ? stripPNGMetadata(out as Data) : out as Data
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

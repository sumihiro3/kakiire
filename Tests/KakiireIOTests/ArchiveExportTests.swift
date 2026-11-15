import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import KakiireCore
@testable import KakiireIO

/// 「ショートカット」の「.kakiire を画像に書き出す」が使う、`.kakiire` のデータから画像を作る処理。
@Suite struct ArchiveExportTests {
    let manifest = Manifest(appVersion: "0.9.0")

    func archive(outputScale: Double = 1, obscure: CGRect? = nil) throws -> (Data, ImageAsset) {
        let base = try ImageImport.asset(from: ImageIOTests.noise(200, 100))
        var annotations: [Annotation] = []
        if let obscure {
            annotations.append(Annotation(name: "o", content: .obscure(ObscureSpec(rect: obscure, mode: .pixelate, strength: 8))))
        }
        let doc = Document(base: BaseImage(asset: base), canvas: Canvas(outputScale: outputScale), annotations: annotations)
        return (try KakiireArchive.write(doc, manifest: manifest), base)
    }

    func image(_ data: Data) -> (CGImage, String?) {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        return (CGImageSourceCreateImageAtIndex(src, 0, nil)!, CGImageSourceGetType(src) as String?)
    }

    @Test func pngAndJpeg() throws {
        let (data, _) = try archive()
        #expect(image(try ImageExport.data(ofArchive: data, format: .png)).1 == UTType.png.identifier)
        #expect(image(try ImageExport.data(ofArchive: data, format: .jpeg)).1 == UTType.jpeg.identifier)
    }

    @Test func scaleReplacesDocumentScale() throws {
        let (data, _) = try archive(outputScale: 2)
        let (kept, _) = image(try ImageExport.data(ofArchive: data, format: .png))
        #expect(kept.width == 400 && kept.height == 200)
        let (half, _) = image(try ImageExport.data(ofArchive: data, format: .png, scale: 0.5))
        #expect(half.width == 100 && half.height == 50)
    }

    @Test func obscuredAreaIsBurnedIn() throws {
        let rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        let (data, base) = try archive(obscure: rect)
        let (out, _) = image(try ImageExport.data(ofArchive: data, format: .png))
        let (orig, _) = image(base.data)
        #expect(Self.pixels(out, rect) != Self.pixels(orig, rect))
    }

    @Test func garbageIsRejected() {
        #expect(throws: (any Error).self) { try ImageExport.data(ofArchive: Data([1, 2, 3]), format: .png) }
    }

    static func pixels(_ img: CGImage, _ rect: CGRect) -> [UInt8] {
        let w = Int(rect.width), h = Int(rect.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img.cropping(to: rect)!, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import KakiireCore
@testable import KakiireIO

@Suite struct ImageIOTests {
    static func noise(_ w: Int, _ h: Int) -> CGImage {
        var state: UInt64 = 7
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            px[i] = UInt8(truncatingIfNeeded: state >> 33)
            px[i + 1] = UInt8(truncatingIfNeeded: state >> 41)
            px[i + 2] = UInt8(truncatingIfNeeded: state >> 49)
        }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(px) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// PNG のチャンク名を順に並べる。
    static func chunkTypes(_ png: Data) -> [String] {
        var types: [String] = []
        var i = 8
        let b = [UInt8](png)
        while i + 8 <= b.count {
            let len = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            types.append(String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? "?")
            i += 12 + len
        }
        return types
    }

    @Test func pngImportKeepsOriginalBytes() throws {
        let png = try ImageExport.data(Self.noise(20, 10), format: .png)
        let asset = try ImageImport.asset(from: png)
        #expect(asset.data == png)
        #expect(asset.pixelSize == CGSize(width: 20, height: 10))
    }

    @Test func jpegImportBecomesPNG() throws {
        let jpg = try ImageExport.data(Self.noise(20, 10), format: .jpeg)
        let asset = try ImageImport.asset(from: jpg)
        let src = CGImageSourceCreateWithData(asset.data as CFData, nil)!
        #expect(CGImageSourceGetType(src) as String? == UTType.png.identifier)
    }

    @Test func exifOrientationIsApplied() throws {
        // 向き 6(90° 回転して表示)の JPEG は、縦横が入れ替わった正立画像になる。
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, Self.noise(40, 20), [kCGImagePropertyOrientation: 6] as CFDictionary)
        CGImageDestinationFinalize(dest)
        let asset = try ImageImport.asset(from: out as Data)
        #expect(asset.pixelSize == CGSize(width: 20, height: 40))
    }

    @Test func garbageIsRejected() {
        #expect(throws: ImageImportError.self) { try ImageImport.asset(from: Data([1, 2, 3])) }
    }

    /// 完了条件②:書き出した PNG に元画像のデータを含むような補助チャンクがない。
    @Test func exportedPNGHasNoAncillaryPayload() throws {
        let base = try ImageImport.asset(from: Self.noise(64, 64))
        let doc = Document(base: BaseImage(asset: base), annotations: [
            Annotation(name: "o", content: .obscure(ObscureSpec(rect: CGRect(x: 0, y: 0, width: 64, height: 64), mode: .pixelate, strength: 8))),
        ])
        let png = try ImageExport.data(of: doc, format: .png)
        let allowed: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "iCCP", "sRGB", "cHRM", "gAMA", "pHYs"]
        let types = Self.chunkTypes(png)
        #expect(types.first == "IHDR" && types.last == "IEND")
        #expect(Set(types).isSubset(of: allowed), "unexpected chunks: \(types)")
        #expect(png != base.data)
    }

    /// JPEG のマーカーを SOS の手前まで並べる。
    static func jpegMarkers(_ jpg: Data) -> [UInt8] {
        let b = [UInt8](jpg)
        var markers: [UInt8] = []
        var i = 2
        while i + 4 <= b.count, b[i] == 0xFF {
            markers.append(b[i + 1])
            if b[i + 1] == 0xDA { break }
            i += 2 + (Int(b[i + 2]) << 8 | Int(b[i + 3]))
        }
        return markers
    }

    /// ImageIO が付ける Exif(APP1)と Photoshop の情報(APP13)を残さない。
    @Test func exportedJPEGHasNoMetadataSegments() throws {
        let doc = Document(base: BaseImage(asset: try ImageImport.asset(from: Self.noise(40, 20))))
        let jpg = try ImageExport.data(of: doc, format: .jpeg)
        let markers = Self.jpegMarkers(jpg)
        #expect(markers.last == 0xDA)
        #expect(!markers.contains(0xE1) && !markers.contains(0xED) && !markers.contains(0xFE), "markers: \(markers.map { String($0, radix: 16) })")
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(jpg as CFData, nil)!, 0, nil)
        #expect(img?.width == 40 && img?.height == 20)
    }

    @Test func brokenJPEGIsReturnedAsIs() {
        let broken = Data([0xFF, 0xD8, 0xFF, 0xE1, 0x00])
        #expect(ImageExport.stripJPEGMetadata(broken) == broken)
    }

    @Test func jpegExportIsOpaque() throws {
        let doc = Document(base: BaseImage(asset: try ImageImport.asset(from: Self.noise(16, 16))))
        let jpg = try ImageExport.data(of: doc, format: .jpeg, jpegQuality: 0.5)
        let src = CGImageSourceCreateWithData(jpg as CFData, nil)!
        #expect(CGImageSourceGetType(src) as String? == UTType.jpeg.identifier)
    }
}

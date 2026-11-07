import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import KakiireCore

enum TestImage {
    /// 1画素ごとに値が変わるノイズ画像。モザイクで「元と一致しない」ことを確かめる用。
    static func noise(width: Int, height: Int, seed: UInt64 = 42) -> CGImage {
        var state = seed
        var px = [UInt8](repeating: 255, count: width * height * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            px[i] = UInt8(truncatingIfNeeded: state >> 33)
            px[i + 1] = UInt8(truncatingIfNeeded: state >> 41)
            px[i + 2] = UInt8(truncatingIfNeeded: state >> 49)
        }
        return make(px, width, height)
    }

    static func solid(width: Int, height: Int, _ c: RGBAColor) -> CGImage {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = c.a
        }
        return make(px, width, height)
    }

    static func make(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func asset(_ image: CGImage) -> ImageAsset {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return ImageAsset(cgImage: image, data: data as Data)
    }

    static func document(_ image: CGImage, _ annotations: [Annotation] = []) -> Document {
        Document(base: BaseImage(asset: asset(image)), annotations: annotations)
    }
}

/// 8bit RGBA(左上原点)で画素を読む。
struct Pixels {
    let width: Int, height: Int
    let data: [UInt8]

    init(_ image: CGImage) {
        let w = image.width, h = image.height
        width = w; height = h
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        data = px
    }

    func rgba(_ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(data[i..<(i + 4)])
    }
}

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
}

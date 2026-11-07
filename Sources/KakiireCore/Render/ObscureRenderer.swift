// Pixelate / box-blur adapted from Sitch (https://github.com/phalladar/Sitch, MIT).
// See THIRD_PARTY_NOTICES.md.
import CoreGraphics
import Foundation

/// モザイク・ぼかしの画素計算。常に伏せる前の元画像から計算する(非破壊)。
///
/// 範囲の外の画素は読まない。境界の外の情報が伏せた範囲に混ざらず、ぼかしの端から元の内容が漏れないようにするため。
public enum ObscureRenderer {
    /// `source` の `region` を伏せた画像(サイズは region と同じ)。
    public static func render(_ source: CGImage, region: PixelRect, mode: ObscureMode, strength: Double) -> CGImage? {
        switch mode {
        case .pixelate: pixelate(source, region, block: max(4, Int(strength.rounded())))
        case .blur: boxBlur(source, region, radius: max(2, Int(strength.rounded())))
        }
    }

    static func pixelate(_ source: CGImage, _ region: PixelRect, block: Int) -> CGImage? {
        guard var buf = PixelBuffer(source, region) else { return nil }
        let w = buf.width, h = buf.height, stride = buf.stride
        buf.pixels.withUnsafeMutableBufferPointer { px in
            var by = 0
            while by < h {
                var bx = 0
                while bx < w {
                    let bw = min(block, w - bx), bh = min(block, h - by)
                    var c0 = 0, c1 = 0, c2 = 0, c3 = 0
                    for y in by..<(by + bh) {
                        var i = y * stride + bx * 4
                        for _ in 0..<bw {
                            c0 += Int(px[i]); c1 += Int(px[i + 1]); c2 += Int(px[i + 2]); c3 += Int(px[i + 3])
                            i += 4
                        }
                    }
                    let n = bw * bh
                    let a0 = UInt8(c0 / n), a1 = UInt8(c1 / n), a2 = UInt8(c2 / n), a3 = UInt8(c3 / n)
                    for y in by..<(by + bh) {
                        var i = y * stride + bx * 4
                        for _ in 0..<bw {
                            px[i] = a0; px[i + 1] = a1; px[i + 2] = a2; px[i + 3] = a3
                            i += 4
                        }
                    }
                    bx += block
                }
                by += block
            }
        }
        return buf.makeImage()
    }

    static func boxBlur(_ source: CGImage, _ region: PixelRect, radius: Int) -> CGImage? {
        guard var buf = PixelBuffer(source, region) else { return nil }
        var tmp = [UInt8](repeating: 0, count: buf.pixels.count)
        let w = buf.width, h = buf.height, s = buf.stride
        // 箱ぼかしを3往復かけるとガウスに近くなる。
        for _ in 0..<3 {
            blurPass(buf.pixels, &tmp, w, h, s, radius, horizontal: true)
            blurPass(tmp, &buf.pixels, w, h, s, radius, horizontal: false)
        }
        return buf.makeImage()
    }

    private static func blurPass(_ src: [UInt8], _ dst: inout [UInt8], _ w: Int, _ h: Int, _ stride: Int,
                                 _ radius: Int, horizontal: Bool) {
        let outer = horizontal ? h : w
        let inner = horizontal ? w : h
        src.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { dst in
                for o in 0..<outer {
                    var s0 = 0, s1 = 0, s2 = 0, s3 = 0, count = 0
                    @inline(__always) func idx(_ i: Int) -> Int { horizontal ? o * stride + i * 4 : i * stride + o * 4 }
                    for i in 0...min(radius, inner - 1) {
                        let k = idx(i)
                        s0 += Int(src[k]); s1 += Int(src[k + 1]); s2 += Int(src[k + 2]); s3 += Int(src[k + 3])
                        count += 1
                    }
                    // 窓は常に [i - radius, i + radius](範囲内に切り詰め)。
                    for i in 0..<inner {
                        let add = i + radius, remove = i - radius - 1
                        if i > 0, add < inner {
                            let k = idx(add)
                            s0 += Int(src[k]); s1 += Int(src[k + 1]); s2 += Int(src[k + 2]); s3 += Int(src[k + 3])
                            count += 1
                        }
                        if remove >= 0 {
                            let k = idx(remove)
                            s0 -= Int(src[k]); s1 -= Int(src[k + 1]); s2 -= Int(src[k + 2]); s3 -= Int(src[k + 3])
                            count -= 1
                        }
                        let d = idx(i)
                        dst[d] = UInt8(s0 / count); dst[d + 1] = UInt8(s1 / count)
                        dst[d + 2] = UInt8(s2 / count); dst[d + 3] = UInt8(s3 / count)
                    }
                }
            }
        }
    }
}

/// 画像の一部を 8bit RGBA(premultiplied、行0が上)で持つ。色空間は元画像のものを保つ。
struct PixelBuffer {
    var pixels: [UInt8]
    let width: Int, height: Int, stride: Int
    let colorSpace: CGColorSpace

    init?(_ source: CGImage, _ region: PixelRect) {
        guard let cropped = source.cropping(to: region.cgRect) else { return nil }
        let w = cropped.width, h = cropped.height, s = w * 4
        let cs = Renderer.colorSpace(for: source)
        width = w; height = h; stride = s; colorSpace = cs
        var px = [UInt8](repeating: 0, count: s * h)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: s, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        pixels = px
    }

    func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

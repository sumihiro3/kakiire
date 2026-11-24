// メイカーコインの図案づくりの下請け。make-coin.py から呼ぶ。
//   cointool qr <文字列> <L|M|Q|H>        QR のマスを 0/1 の行で出す(上の行から。余白なし)
//   cointool glyphs <フォント> <文字列>    字の輪郭を SVG のパスで出す(1000 = 1em、y 下向き、JSON)
//                                         フォントは "rounded:bold" か "name:HiraginoSans-W7" の形
//   cointool decode <PNG> [縮小後の幅 ぼかし半径]   QR を読んで中身を出す
import AppKit
import CoreImage
import CoreText
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func qr(_ text: String, level: String) {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(text.data(using: .isoLatin1)!, forKey: "inputMessage")
    filter.setValue(level, forKey: "inputCorrectionLevel")
    let image = filter.outputImage!
    let size = Int(image.extent.width)
    guard let cg = CIContext().createCGImage(image, from: image.extent) else { fail("QR を描けない") }
    var pixels = [UInt8](repeating: 0, count: size * size)
    let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    // CoreImage は周りに 1 マスの余白を付ける。余白は図案の側で付け直すので、ここでは外す。
    for y in 1..<(size - 1) {
        print((1..<(size - 1)).map { pixels[y * size + $0] < 128 ? "1" : "0" }.joined())
    }
}

func font(_ spec: String) -> CTFont {
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { fail("フォントの指定は rounded:bold か name:HiraginoSans-W7 の形で") }
    if parts[0] == "name" {
        return CTFontCreateWithName(parts[1] as CFString, 1000, nil)
    }
    let weights: [String: NSFont.Weight] = ["medium": .medium, "semibold": .semibold, "bold": .bold,
                                            "heavy": .heavy, "black": .black]
    guard let weight = weights[parts[1]] else { fail("太さは medium / semibold / bold / heavy / black") }
    let base = NSFont.systemFont(ofSize: 1000, weight: weight)
    let design: NSFontDescriptor.SystemDesign = parts[0] == "rounded" ? .rounded : .default
    let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
    return NSFont(descriptor: descriptor, size: 1000)! as CTFont
}

func glyphs(_ spec: String, text: String) {
    let ctFont = font(spec)
    var flip = CGAffineTransform(scaleX: 1, y: -1)
    var out: [[String: Any]] = []
    for scalar in text.unicodeScalars {
        var chars = Array(String(scalar).utf16)
        var glyph = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &chars, &glyph, chars.count), glyph[0] != 0 else {
            fail("\(spec) に「\(scalar)」の字がない")
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, [glyph[0]], &advance, 1)
        var d = ""
        var box = CGRect.null
        if let path = CTFontCreatePathForGlyph(ctFont, glyph[0], &flip) {
            box = path.boundingBoxOfPath
            func p(_ pt: CGPoint) -> String { String(format: "%.1f %.1f", pt.x, pt.y) }
            path.applyWithBlock { element in
                let pts = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: d += "M\(p(pts[0]))"
                case .addLineToPoint: d += "L\(p(pts[0]))"
                case .addQuadCurveToPoint: d += "Q\(p(pts[0])) \(p(pts[1]))"
                case .addCurveToPoint: d += "C\(p(pts[0])) \(p(pts[1])) \(p(pts[2]))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
        }
        out.append(["ch": String(scalar), "d": d, "adv": Double(advance.width),
                    "box": box.isNull ? [0, 0, 0, 0] : [Double(box.minX), Double(box.minY), Double(box.maxX), Double(box.maxY)]])
    }
    let result: [String: Any] = ["font": CTFontCopyPostScriptName(ctFont) as String,
                                 "cap": Double(CTFontGetCapHeight(ctFont)), "glyphs": out]
    print(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
}

func decode(_ path: String, width: Int?, blur: Double) {
    guard var image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { fail("\(path) を開けない") }
    if let width {
        // 印刷のにじみと、離して撮ったときの粗さのつもりで、ぼかしてから縮める。
        image = image.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: image.extent)
        let k = CGFloat(width) / image.extent.width
        image = image.transformed(by: CGAffineTransform(scaleX: k, y: k))
    }
    guard let cg = CIContext().createCGImage(image, from: image.extent) else { fail("画像を作れない") }
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try! VNImageRequestHandler(cgImage: cg).perform([request])
    let found = (request.results ?? []).compactMap(\.payloadStringValue)
    print(found.isEmpty ? "(読めない)" : found.joined(separator: "\n"))
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "qr" where args.count == 4: qr(args[2], level: args[3])
case "glyphs" where args.count == 4: glyphs(args[2], text: args[3])
case "decode" where args.count == 3: decode(args[2], width: nil, blur: 0)
case "decode" where args.count == 5: decode(args[2], width: Int(args[3]), blur: Double(args[4]) ?? 0)
default: fail("使い方: cointool qr <文字列> <水準> | glyphs <フォント> <文字列> | decode <PNG> [幅 ぼかし]")
}

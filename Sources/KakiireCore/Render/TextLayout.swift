import CoreGraphics
import CoreText
import Foundation

/// テキスト注釈の寸法計算と描画。AppKit を使わず CoreText だけで行う。
public enum TextLayout {
    /// 白フチの太さ(フォントサイズに対する割合、%)。
    static let outlinePercent: CGFloat = 22

    public static func font(size: Double, bold: Bool) -> CTFont {
        let kind: CTFontUIFontType = bold ? .emphasizedSystem : .system
        return CTFontCreateUIFontForLanguage(kind, CGFloat(size), nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
    }

    /// 文字の外側に足す余白。白フチがはみ出す分。
    public static func padding(_ spec: TextSpec) -> CGFloat {
        spec.outline ? CGFloat(spec.fontSize) * outlinePercent / 100 * 0.6 : 2
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
    }

    static func lines(_ spec: TextSpec, font: CTFont, attributes: [CFString: Any]) -> [CTLine] {
        let text = spec.text.isEmpty ? " " : spec.text
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var attrs = attributes
            attrs[kCTFontAttributeName] = font
            let s = CFAttributedStringCreate(nil, (line.isEmpty ? " " : String(line)) as CFString, attrs as CFDictionary)!
            return CTLineCreateWithAttributedString(s)
        }
    }

    /// 白フチを含む外形(origin が左上)。
    public static func bounds(_ spec: TextSpec) -> CGRect {
        let f = font(size: spec.fontSize, bold: spec.bold)
        let ls = lines(spec, font: f, attributes: [:])
        let w = ls.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        let pad = padding(spec)
        let h = lineHeight(f) * CGFloat(ls.count)
        return CGRect(x: spec.origin.x, y: spec.origin.y, width: w.rounded(.up) + pad * 2, height: h + pad * 2)
    }

    /// 左上原点・y 下向きの context に描く。
    public static func draw(_ spec: TextSpec, in ctx: CGContext) {
        let f = font(size: spec.fontSize, bold: spec.bold)
        let pad = padding(spec)
        let lh = lineHeight(f)
        let ascent = CTFontGetAscent(f)

        ctx.saveGState()
        defer { ctx.restoreGState() }
        // y 下向きの context でも文字を正立させる。
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setLineJoin(.round)

        func drawLines(_ attrs: [CFString: Any]) {
            for (i, line) in lines(spec, font: f, attributes: attrs).enumerated() {
                ctx.textPosition = CGPoint(x: spec.origin.x + pad, y: spec.origin.y + pad + ascent + lh * CGFloat(i))
                CTLineDraw(line, ctx)
            }
        }

        if spec.outline {
            let outline = spec.color == .white ? RGBAColor.black : RGBAColor.white
            drawLines([
                kCTStrokeWidthAttributeName: outlinePercent,
                kCTStrokeColorAttributeName: outline.cgColor,
            ])
        }
        drawLines([kCTForegroundColorAttributeName: spec.color.cgColor])
    }
}

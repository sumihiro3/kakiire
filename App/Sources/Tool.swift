import AppKit
import KakiireCore

/// キャンバスで使う道具。
enum Tool: Int, CaseIterable {
    case select, arrow, line, rect, ellipse, text, highlighter, pen, stamp, pixelate, blur, crop

    var title: String {
        switch self {
        case .select: "選択"
        case .arrow: "矢印"
        case .line: "線"
        case .rect: "矩形"
        case .ellipse: "楕円"
        case .text: "テキスト"
        case .highlighter: "ハイライター"
        case .pen: "ペン"
        case .stamp: "番号スタンプ"
        case .pixelate: "モザイク"
        case .blur: "ぼかし"
        case .crop: "切り抜き"
        }
    }

    /// 修飾キーなしで押すと切り替わるキー。
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .text: "t"
        case .highlighter: "h"
        case .pen: "p"
        case .stamp: "n"
        case .pixelate: "m"
        case .blur: "b"
        case .crop: "c"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .pen: "pencil.tip"
        case .stamp: "1.circle"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
        case .crop: "crop"
        }
    }

    static func forKey(_ s: String) -> Tool? { allCases.first { $0.key == s.lowercased() } }
}

/// 線の太さの3段階。画像の大きさ(Retina のスクショは画素が倍)に合わせて実際の値を決める。
enum Weight: Int, CaseIterable {
    case thin, medium, thick

    var title: String { ["細", "中", "太"][rawValue] }
    var stroke: Double { [4, 8, 14][rawValue] }
    /// 先細り矢印は尾の幅なので、線より太くしないと Skitch らしく見えない(Sitch の既定は 20)。
    var arrowStroke: Double { [12, 20, 32][rawValue] }
    var fontSize: Double { [20, 30, 44][rawValue] }
    var highlighter: Double { [16, 28, 44][rawValue] }
    var stampDiameter: Double { [28, 40, 56][rawValue] }
}

/// 新しく描く注釈の見た目。選択中の注釈にも反映する。
struct DrawingStyle {
    var color: RGBAColor = .pink
    var weight: Weight = .medium
    /// 元画像が大きいほど線を太くする係数。
    var pixelScale: Double = 1

    var strokeWidth: Double { weight.stroke * pixelScale }
    var arrowWidth: Double { weight.arrowStroke * pixelScale }
    var fontSize: Double { weight.fontSize * pixelScale }
    var obscureStrength: Double { 12 * pixelScale }
    var highlighterWidth: Double { weight.highlighter * pixelScale }
    var stampDiameter: Double { weight.stampDiameter * pixelScale }

    static func pixelScale(for size: CGSize) -> Double {
        max(1, (max(size.width, size.height) / 1800).rounded())
    }

    /// `tool` で `a` から `b` までドラッグしたときの中身。
    func content(for tool: Tool, from a: CGPoint, to b: CGPoint, constrain: Bool) -> AnnotationContent? {
        let end = constrain ? Annotation.snap45(b, around: a) : b
        var rect = CGRect(corner: a, b)
        if constrain {
            let side = max(rect.width, rect.height)
            rect = CGRect(corner: a, CGPoint(x: a.x + (b.x < a.x ? -side : side), y: a.y + (b.y < a.y ? -side : side)))
        }
        switch tool {
        case .arrow: return .arrow(ArrowSpec(from: a, to: end, color: color, width: arrowWidth))
        case .line: return .line(LineSpec(from: a, to: end, color: color, width: strokeWidth))
        case .rect: return .rect(ShapeSpec(rect: rect, color: color, width: strokeWidth))
        case .ellipse: return .ellipse(ShapeSpec(rect: rect, color: color, width: strokeWidth))
        case .pixelate: return .obscure(ObscureSpec(rect: rect, mode: .pixelate, strength: obscureStrength))
        case .blur: return .obscure(ObscureSpec(rect: rect, mode: .blur, strength: obscureStrength * 1.4))
        case .select, .text, .highlighter, .pen, .stamp, .crop: return nil
        }
    }

    /// ハイライター・ペンの点列から中身を作る。
    func stroke(for tool: Tool, points: [CGPoint]) -> AnnotationContent? {
        switch tool {
        case .highlighter: .highlighter(StrokeSpec(points: points, color: color, width: highlighterWidth))
        case .pen: .pen(StrokeSpec(points: points, color: color, width: strokeWidth))
        default: nil
        }
    }

    /// 選択中の注釈に色・太さを当てたもの。
    func applying(color newColor: RGBAColor? = nil, weight newWeight: Weight? = nil, to a: Annotation) -> Annotation {
        let w = newWeight.map { $0.stroke * pixelScale }
        let aw = newWeight.map { $0.arrowStroke * pixelScale }
        let fs = newWeight.map { $0.fontSize * pixelScale }
        switch a.content {
        case .arrow(var s): s.color = newColor ?? s.color; s.width = aw ?? s.width; return a.with(content: .arrow(s))
        case .line(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; return a.with(content: .line(s))
        case .rect(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; return a.with(content: .rect(s))
        case .ellipse(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; return a.with(content: .ellipse(s))
        case .text(var s): s.color = newColor ?? s.color; s.fontSize = fs ?? s.fontSize; return a.with(content: .text(s))
        case .highlighter(var s):
            s.color = newColor ?? s.color; s.width = newWeight.map { $0.highlighter * pixelScale } ?? s.width
            return a.with(content: .highlighter(s))
        case .pen(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; return a.with(content: .pen(s))
        case .stamp(var s):
            s.color = newColor ?? s.color; s.diameter = newWeight.map { $0.stampDiameter * pixelScale } ?? s.diameter
            return a.with(content: .stamp(s))
        case .obscure, .image, .unknown: return a
        }
    }
}

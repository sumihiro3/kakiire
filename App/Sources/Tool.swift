import AppKit
import KakiireCore

/// キャンバスで使う道具。
enum Tool: Int, CaseIterable {
    case select, arrow, line, rect, ellipse, text, pixelate, blur

    var title: String {
        switch self {
        case .select: "選択"
        case .arrow: "矢印"
        case .line: "線"
        case .rect: "矩形"
        case .ellipse: "楕円"
        case .text: "テキスト"
        case .pixelate: "モザイク"
        case .blur: "ぼかし"
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
        case .pixelate: "m"
        case .blur: "b"
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
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
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
        case .select, .text: return nil
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
        case .obscure, .unknown: return a
        }
    }
}

import AppKit
import KakiireCore

/// キャンバスで使う道具。
enum Tool: Int, CaseIterable {
    case select, arrow, line, rect, ellipse, text, highlighter, pen, stamp, pixelate, blur, crop

    var title: String {
        switch self {
        case .select: String(localized: "選択")
        case .arrow: String(localized: "矢印")
        case .line: String(localized: "線")
        case .rect: String(localized: "矩形")
        case .ellipse: String(localized: "楕円")
        case .text: String(localized: "テキスト")
        case .highlighter: String(localized: "ハイライター")
        case .pen: String(localized: "ペン")
        case .stamp: String(localized: "番号スタンプ")
        case .pixelate: String(localized: "モザイク")
        case .blur: String(localized: "ぼかし")
        case .crop: String(localized: "切り抜き")
        }
    }

    /// ツールチップに出す使い方。
    var hint: String {
        switch self {
        case .select: String(localized: "クリックで選ぶ、ドラッグで動かす。Shift+クリックで選択に追加")
        case .arrow: String(localized: "ドラッグして矢印を描く。Shift で 45° 刻み")
        case .line: String(localized: "ドラッグして線を描く。Shift で 45° 刻み")
        case .rect: String(localized: "ドラッグして矩形を描く。Shift で正方形")
        case .ellipse: String(localized: "ドラッグして楕円を描く。Shift で正円")
        case .text: String(localized: "クリックして文字を入力。Esc か ⌘Return で確定")
        case .highlighter: String(localized: "なぞって蛍光ペンで塗る。下の文字は透ける")
        case .pen: String(localized: "なぞって自由に描く")
        case .stamp: String(localized: "クリックするたびに 1, 2, 3… と番号を置く")
        case .pixelate: String(localized: "ドラッグした範囲をモザイクで隠す")
        case .blur: String(localized: "ドラッグした範囲をぼかして隠す")
        case .crop: String(localized: "ドラッグで範囲を決め、Return で確定、Esc で取り消し")
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

    var title: String { [String(localized: "細"), String(localized: "中"), String(localized: "太")][rawValue] }
    var stroke: Double { [4, 8, 14][rawValue] }
    /// 先細り矢印は尾の幅なので、線より太くしないと Skitch らしく見えない(Sitch の既定は 20)。
    var arrowStroke: Double { [12, 20, 32][rawValue] }
    var highlighter: Double { [16, 28, 44][rawValue] }
    var stampDiameter: Double { [28, 40, 56][rawValue] }
}

/// 文字の大きさの段(pt。実際は pixelScale 倍)。
enum FontSizes {
    static let steps: [Double] = [12, 16, 20, 24, 30, 36, 44, 56, 72]
    static let defaultIndex = 4

    /// `size` に最も近い段。
    static func nearestIndex(to size: Double, pixelScale: Double) -> Int {
        steps.indices.min { abs(steps[$0] * pixelScale - size) < abs(steps[$1] * pixelScale - size) } ?? defaultIndex
    }
}

/// モザイク・ぼかしの強さの3段階。
enum ObscureLevel: Int, CaseIterable {
    case weak, medium, strong

    /// モザイクのマスの大きさ(px)。ぼかしはこの 1.4 倍の半径にする。
    var pixelate: Double { [6, 12, 24][rawValue] }

    func strength(_ mode: ObscureMode, pixelScale: Double) -> Double {
        pixelate * pixelScale * (mode == .blur ? 1.4 : 1)
    }
}

/// スタイルボタン(色の隣)が何を変えるか。今のツールか、選択中の注釈で決まる。
enum StyleTarget {
    case stroke, text, obscure
    /// 画像オーバーレイの枠線と影。
    case image
}

/// 画像オーバーレイの枠線の段。
enum ImageFrame: Int, CaseIterable {
    case none, thin, medium, thick

    /// 枠線の幅(pt。実際は pixelScale 倍)。
    var width: Double { [0, 2, 4, 8][rawValue] }
}

/// 画像オーバーレイの影のぼかしの半径(pt。実際は pixelScale 倍)。
let imageShadowRadius = 12.0

extension Tool {
    /// 線の種類(破線など)を選べるツール。
    var supportsDash: Bool { [.arrow, .line, .rect, .ellipse, .pen].contains(self) }

    /// このツールで描く種類の注釈か。作図ツールのまま、同じ種類の注釈だけをつかんで動かせるようにする。
    func owns(_ content: AnnotationContent) -> Bool {
        switch (self, content) {
        case (.arrow, .arrow), (.line, .line), (.rect, .rect), (.ellipse, .ellipse), (.text, .text),
             (.highlighter, .highlighter), (.pen, .pen), (.stamp, .stamp):
            true
        case (.pixelate, .obscure(let o)): o.mode == .pixelate
        case (.blur, .obscure(let o)): o.mode == .blur
        default: false
        }
    }

    var styleTarget: StyleTarget {
        switch self {
        case .text: .text
        case .pixelate, .blur: .obscure
        default: .stroke
        }
    }
}

extension AnnotationContent {
    var supportsDash: Bool {
        switch self {
        case .arrow, .line, .rect, .ellipse, .pen: true
        default: false
        }
    }

    var styleTarget: StyleTarget? {
        switch self {
        case .text: .text
        case .obscure: .obscure
        case .image: .image
        case .unknown: nil
        default: .stroke
        }
    }
}

/// スタイルの変更1回分。nil の項目は変えない。
struct StyleChange {
    var color: RGBAColor?
    var weight: Weight?
    var fontIndex: Int?
    var outline: Bool?
    var arrowOutline: Bool?
    var obscureLevel: ObscureLevel?
    var dash: LineDash?
    var imageFrame: ImageFrame?
    var imageShadow: Bool?
}

/// 新しく描く注釈の見た目。選択中の注釈にも反映する。
struct DrawingStyle {
    var color: RGBAColor = .pink
    var weight: Weight = .medium
    var fontIndex = FontSizes.defaultIndex
    /// 文字の袋文字(縁取り)。
    var outline = true
    /// 矢印の白い縁取り。文字の袋文字とは別に持つ(既定が違うため)。
    var arrowOutline = false
    var obscureLevel: ObscureLevel = .medium
    var dash: LineDash = .solid
    /// 新しく挿入する画像の枠線と影。最後に選んだものを使う。
    var imageFrame: ImageFrame = .none
    var imageShadow = false
    /// 元画像が大きいほど線を太くする係数。
    var pixelScale: Double = 1

    var strokeWidth: Double { weight.stroke * pixelScale }
    var arrowWidth: Double { weight.arrowStroke * pixelScale }
    var fontSize: Double { FontSizes.steps[fontIndex] * pixelScale }
    var highlighterWidth: Double { weight.highlighter * pixelScale }
    var stampDiameter: Double { weight.stampDiameter * pixelScale }
    var imageBorder: ImageBorder? { imageFrame == .none ? nil : ImageBorder(color: color, width: imageFrame.width * pixelScale) }
    var imageShadowValue: Double { imageShadow ? imageShadowRadius * pixelScale : 0 }

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
        case .arrow: return .arrow(ArrowSpec(from: a, to: end, color: color, width: arrowWidth, dash: dash, outline: arrowOutline))
        case .line: return .line(LineSpec(from: a, to: end, color: color, width: strokeWidth, dash: dash))
        case .rect: return .rect(ShapeSpec(rect: rect, color: color, width: strokeWidth, dash: dash))
        case .ellipse: return .ellipse(ShapeSpec(rect: rect, color: color, width: strokeWidth, dash: dash))
        case .pixelate: return .obscure(ObscureSpec(rect: rect, mode: .pixelate, strength: obscureLevel.strength(.pixelate, pixelScale: pixelScale)))
        case .blur: return .obscure(ObscureSpec(rect: rect, mode: .blur, strength: obscureLevel.strength(.blur, pixelScale: pixelScale)))
        case .select, .text, .highlighter, .pen, .stamp, .crop: return nil
        }
    }

    /// ハイライター・ペンの点列から中身を作る。
    func stroke(for tool: Tool, points: [CGPoint]) -> AnnotationContent? {
        switch tool {
        case .highlighter: .highlighter(StrokeSpec(points: points, color: color, width: highlighterWidth))
        case .pen: .pen(StrokeSpec(points: points, color: color, width: strokeWidth, dash: dash))
        default: nil
        }
    }

    /// 今のスタイルに `change` を重ねたもの。
    func merged(_ change: StyleChange) -> DrawingStyle {
        var s = self
        if let c = change.color { s.color = c }
        if let w = change.weight { s.weight = w }
        if let f = change.fontIndex { s.fontIndex = f }
        if let o = change.outline { s.outline = o }
        if let o = change.arrowOutline { s.arrowOutline = o }
        if let l = change.obscureLevel { s.obscureLevel = l }
        if let d = change.dash { s.dash = d }
        if let f = change.imageFrame { s.imageFrame = f }
        if let sh = change.imageShadow { s.imageShadow = sh }
        return s
    }

    /// 選択中の注釈に `change` を当てたもの。種類に関係ない項目は無視する。
    func applying(_ change: StyleChange, to a: Annotation) -> Annotation {
        let newColor = change.color, newWeight = change.weight, d = change.dash
        let w = newWeight.map { $0.stroke * pixelScale }
        let aw = newWeight.map { $0.arrowStroke * pixelScale }
        switch a.content {
        case .arrow(var s):
            s.color = newColor ?? s.color; s.width = aw ?? s.width; s.dash = d ?? s.dash
            s.outline = change.arrowOutline ?? s.outline
            return a.with(content: .arrow(s))
        case .line(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; s.dash = d ?? s.dash; return a.with(content: .line(s))
        case .rect(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; s.dash = d ?? s.dash; return a.with(content: .rect(s))
        case .ellipse(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; s.dash = d ?? s.dash; return a.with(content: .ellipse(s))
        case .text(var s):
            s.color = newColor ?? s.color
            s.fontSize = change.fontIndex.map { FontSizes.steps[$0] * pixelScale } ?? s.fontSize
            s.outline = change.outline ?? s.outline
            return a.with(content: .text(s))
        case .highlighter(var s):
            s.color = newColor ?? s.color; s.width = newWeight.map { $0.highlighter * pixelScale } ?? s.width
            return a.with(content: .highlighter(s))
        case .pen(var s): s.color = newColor ?? s.color; s.width = w ?? s.width; s.dash = d ?? s.dash; return a.with(content: .pen(s))
        case .stamp(var s):
            s.color = newColor ?? s.color; s.diameter = newWeight.map { $0.stampDiameter * pixelScale } ?? s.diameter
            return a.with(content: .stamp(s))
        case .obscure(var s):
            s.strength = change.obscureLevel.map { $0.strength(s.mode, pixelScale: pixelScale) } ?? s.strength
            return a.with(content: .obscure(s))
        case .image(var s):
            // 色は枠のある画像だけに当てる(色を選んだだけで枠が付くと驚くため)。
            if let c = newColor, var b = s.border { b.color = c; s.border = b }
            if let f = change.imageFrame {
                s.border = f == .none ? nil : ImageBorder(color: s.border?.color ?? color, width: f.width * pixelScale)
            }
            if let sh = change.imageShadow { s.shadow = sh ? imageShadowRadius * pixelScale : 0 }
            return a.with(content: .image(s))
        case .unknown: return a
        }
    }
}

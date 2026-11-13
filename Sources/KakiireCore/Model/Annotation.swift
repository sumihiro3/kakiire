import CoreGraphics
import Foundation

/// 注釈1つ。配列内の位置が重なり順(先頭が最背面)。座標はすべて元画像のピクセル座標(左上原点・y 下向き)。
public struct Annotation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var hidden: Bool
    public var locked: Bool
    public var content: AnnotationContent

    public init(id: UUID = UUID(), name: String, hidden: Bool = false, locked: Bool = false, content: AnnotationContent) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.locked = locked
        self.content = content
    }

    /// 同じ id のまま中身だけ差し替えたコピー。
    public func with(content: AnnotationContent) -> Annotation {
        var a = self
        a.content = content
        return a
    }
}

/// 注釈の種類ごとの中身。
public enum AnnotationContent: Sendable, Equatable {
    case arrow(ArrowSpec)
    case line(LineSpec)
    case rect(ShapeSpec)
    case ellipse(ShapeSpec)
    case text(TextSpec)
    case obscure(ObscureSpec)
    /// 乗算で塗る蛍光ペン。下の画像・効果が透ける。
    case highlighter(StrokeSpec)
    case pen(StrokeSpec)
    /// 連番の丸。
    case stamp(StampSpec)
    /// 画像オーバーレイ。モザイク・ぼかしは元画像とこれを合わせたものから計算する。
    case image(ImageSpec)
    /// 知らない type。JSON をそのまま保持し、再保存しても消さない。
    case unknown(type: String, raw: JSONValue)

    /// JSON の `type` の値。
    public var typeName: String {
        switch self {
        case .arrow: "arrow"
        case .line: "line"
        case .rect: "rect"
        case .ellipse: "ellipse"
        case .text: "text"
        case .obscure: "obscure"
        case .highlighter: "highlighter"
        case .pen: "pen"
        case .stamp: "stamp"
        case .image: "image"
        case .unknown(let type, _): type
        }
    }

    /// 描画のグループ。配列の位置より優先し、グループの順に描く。
    public var renderGroup: RenderGroup {
        switch self {
        case .image: .image
        case .obscure: .effect
        case .highlighter: .highlight
        default: .shape
        }
    }

    /// モザイク・ぼかしなど、元画像から計算して図形より下に描くもの。
    public var isEffect: Bool { renderGroup == .effect }

    /// 既定の名前を数えるときの種類。モザイクとぼかしは別に数える。
    public var kindKey: String {
        if case .obscure(let s) = self { return "obscure.\(s.mode.rawValue)" }
        return typeName
    }
}

/// 矢印の頭の形。
public enum ArrowHead: String, Sendable, Codable, CaseIterable {
    /// Skitch 風の先細り。
    case tapered
    /// 線と開いた矢じり。
    case open
}

/// 線の種類。間隔は線幅の倍数で決める。
public enum LineDash: String, Sendable, Codable, CaseIterable {
    case solid, dashed, dotted, dashDot

    /// 線幅 `w` のときの `setLineDash` の長さ。実線は空。点線は丸い端で点に見せるため長さ 0 の線分を使う。
    public func lengths(width w: CGFloat) -> [CGFloat] {
        switch self {
        case .solid: []
        case .dashed: [w * 3, w * 2]
        case .dotted: [0, w * 2]
        case .dashDot: [w * 4, w * 1.5, 0, w * 1.5]
        }
    }
}

public struct ArrowSpec: Sendable, Equatable {
    public var from: CGPoint
    public var to: CGPoint
    public var color: RGBAColor
    public var width: Double
    public var head: ArrowHead
    /// 実線以外のときは、先細りの形でも「線 + 開いた矢じり」で描く。
    public var dash: LineDash
    /// 白い縁取り(袋文字と同じ考え方)。暗い画像や同じ色の多い画像でも矢印が埋もれないようにする。
    public var outline: Bool

    public init(from: CGPoint, to: CGPoint, color: RGBAColor, width: Double, head: ArrowHead = .tapered,
                dash: LineDash = .solid, outline: Bool = false) {
        self.from = from; self.to = to; self.color = color; self.width = width; self.head = head; self.dash = dash
        self.outline = outline
    }

    /// 縁取りが矢印の外にはみ出す幅。描画・当たり判定・描画範囲はこれだけを使う。
    public var outlineBand: CGFloat { outline ? max(2, CGFloat(width) * 0.15) : 0 }

    /// 縁の色。白い矢印に白い縁では見えないので、そのときだけ黒にする(文字の袋文字と同じ決まり)。
    public var outlineColor: RGBAColor { color == .white ? .black : .white }
}

public struct LineSpec: Sendable, Equatable {
    public var from: CGPoint
    public var to: CGPoint
    public var color: RGBAColor
    public var width: Double
    public var dash: LineDash

    public init(from: CGPoint, to: CGPoint, color: RGBAColor, width: Double, dash: LineDash = .solid) {
        self.from = from; self.to = to; self.color = color; self.width = width; self.dash = dash
    }
}

/// 矩形・楕円の共通仕様。
public struct ShapeSpec: Sendable, Equatable {
    public var rect: CGRect
    public var color: RGBAColor
    public var width: Double
    public var fill: RGBAColor?
    public var dash: LineDash

    public init(rect: CGRect, color: RGBAColor, width: Double, fill: RGBAColor? = nil, dash: LineDash = .solid) {
        self.rect = rect; self.color = color; self.width = width; self.fill = fill; self.dash = dash
    }
}

public struct TextSpec: Sendable, Equatable {
    /// 文字ブロックの左上。
    public var origin: CGPoint
    public var text: String
    public var color: RGBAColor
    public var fontSize: Double
    public var bold: Bool
    /// Skitch 風の白フチ。
    public var outline: Bool

    public init(origin: CGPoint, text: String, color: RGBAColor, fontSize: Double, bold: Bool = true, outline: Bool = true) {
        self.origin = origin; self.text = text; self.color = color
        self.fontSize = fontSize; self.bold = bold; self.outline = outline
    }
}

public enum ObscureMode: String, Sendable, Codable, CaseIterable {
    case pixelate
    case blur
}

public struct ObscureSpec: Sendable, Equatable {
    public var rect: CGRect
    public var mode: ObscureMode
    /// pixelate はブロックの一辺(px)、blur は半径(px)。
    public var strength: Double

    public init(rect: CGRect, mode: ObscureMode, strength: Double) {
        self.rect = rect; self.mode = mode; self.strength = strength
    }
}

/// 描く順のグループ(下から)。並べ替えはグループの中だけで意味を持つ。
public enum RenderGroup: Int, Sendable, CaseIterable, Comparable {
    /// 画像オーバーレイ。元画像の直上。
    case image
    /// モザイク・ぼかし。元画像と画像オーバーレイから計算する。
    case effect
    /// ハイライター。乗算なので図形より下に置く。
    case highlight
    case shape

    public static func < (a: RenderGroup, b: RenderGroup) -> Bool { a.rawValue < b.rawValue }
}

/// ハイライター・ペンの点列。
public struct StrokeSpec: Sendable, Equatable {
    public var points: [CGPoint]
    public var color: RGBAColor
    public var width: Double
    public var dash: LineDash

    public init(points: [CGPoint], color: RGBAColor, width: Double, dash: LineDash = .solid) {
        self.points = points; self.color = color; self.width = width; self.dash = dash
    }
}

/// スタンプの種類。数字と英字は置くたびに進み、記号と絵文字は進まない。
public enum StampKind: Sendable, Hashable {
    case number
    /// A, B, … Z, AA, AB …
    case letter
    /// ✓ ✗ ? ! など。数字と同じく色の丸に白い文字で描く。
    case symbol(String)
    /// 丸を描かず、絵文字だけを描く。色は効かない。
    case emoji(String)

    /// 置くたびに番号が進むか。
    public var isSequential: Bool { self == .number || self == .letter }
}

public struct StampSpec: Sendable, Equatable {
    public var center: CGPoint
    /// 数字・英字の順番(1 始まり)。記号・絵文字では使わない。
    public var number: Int
    public var color: RGBAColor
    public var diameter: Double
    public var kind: StampKind

    public init(center: CGPoint, number: Int, color: RGBAColor, diameter: Double, kind: StampKind = .number) {
        self.center = center; self.number = number; self.color = color; self.diameter = diameter; self.kind = kind
    }

    /// スタンプに描く文字。
    public var label: String {
        switch kind {
        case .number: String(number)
        case .letter: Self.letters(number)
        case .symbol(let s), .emoji(let s): s
        }
    }

    /// 入力した文字を番号に読む(`label` の逆)。数字は 1…999、英字は A…ZZZ(小文字可)。
    /// 円に収まるよう 3 文字までに限る。全角は半角に直す。記号・絵文字や読めない文字は nil。
    public static func number(fromLabel text: String, kind: StampKind) -> Int? {
        let s = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .trimmingCharacters(in: .whitespaces)
        guard (1...3).contains(s.count) else { return nil }
        switch kind {
        case .number:
            guard s.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(s), n >= 1 else { return nil }
            return n
        case .letter:
            var n = 0
            for c in s.uppercased().unicodeScalars {
                guard ("A"..."Z").contains(c) else { return nil }
                n = n * 26 + Int(c.value - 64)
            }
            return n
        case .symbol, .emoji:
            return nil
        }
    }

    /// 1→A … 26→Z、27→AA(表計算の列名と同じ数え方)。
    static func letters(_ n: Int) -> String {
        var n = max(1, n), out = ""
        while n > 0 {
            n -= 1
            out = String(UnicodeScalar(UInt8(65 + n % 26))) + out
            n /= 26
        }
        return out
    }
}

/// 枠線を画像のどちら側に描くか。
public enum BorderPosition: String, Sendable, Hashable, Codable, CaseIterable {
    /// 画像の縁に重ねて描く。外形は変わらない。
    case inside
    /// 画像を囲むように描く。画像は欠けないが、枠の分だけ外へ広がる。
    case outside
}

/// 画像オーバーレイの枠線。
public struct ImageBorder: Sendable, Hashable {
    public var color: RGBAColor
    public var width: Double
    public var position: BorderPosition

    public init(color: RGBAColor, width: Double, position: BorderPosition = .inside) {
        self.color = color; self.width = width; self.position = position
    }

    /// 枠線の外側の縁。外側に描くときは `rect` から枠の幅だけ広がる。
    func outerRect(of rect: CGRect) -> CGRect {
        position == .outside ? rect.insetBy(dx: -CGFloat(width), dy: -CGFloat(width)) : rect
    }
}

/// 画像オーバーレイ。回転・反転は元画像と同じく中身ごとかける(上に掛けたモザイクとずれないように)。
public struct ImageSpec: Sendable, Equatable {
    public var asset: ImageAsset
    /// 向きを変えた後の画像を置く範囲。
    public var rect: CGRect
    public var rotation: Rotation
    public var flipH: Bool
    public var flipV: Bool
    /// 枠線。nil なら枠なし。
    public var border: ImageBorder?
    /// 影のぼかしの半径(px)。0 なら影なし。下へのずれはこの 0.3 倍。
    public var shadow: Double

    public init(asset: ImageAsset, rect: CGRect, rotation: Rotation = .r0, flipH: Bool = false, flipV: Bool = false,
                border: ImageBorder? = nil, shadow: Double = 0) {
        self.asset = asset; self.rect = rect; self.rotation = rotation; self.flipH = flipH; self.flipV = flipV
        self.border = border; self.shadow = shadow
    }

    /// 影の下へのずれ(px)。
    public var shadowOffset: CGFloat { CGFloat(shadow) * 0.3 }

    /// 外側の枠線と影まで含めて描く範囲。当たり判定は `rect` のまま。
    public var drawnBounds: CGRect {
        let r = border?.outerRect(of: rect.standardized) ?? rect.standardized
        guard shadow > 0 else { return r }
        // CoreGraphics の影はぼかしの半径より少し外まで届くので、余裕を持たせる。
        let reach = CGFloat(shadow) * 1.5
        return r.union(r.offsetBy(dx: 0, dy: shadowOffset).insetBy(dx: -reach, dy: -reach))
    }

    /// 向きの計算・描画は元画像と共通の `BaseImage` で行う。
    public var source: BaseImage {
        get { BaseImage(asset: asset, rotation: rotation, flipH: flipH, flipV: flipV) }
        set { asset = newValue.asset; rotation = newValue.rotation; flipH = newValue.flipH; flipV = newValue.flipV }
    }

    /// `.kakiire` 内のファイル名。内容の SHA-256 で重複を除く。
    public var assetPath: String { "assets/\(asset.sha256).png" }
}

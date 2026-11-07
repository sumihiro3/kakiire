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
        case .unknown(let type, _): type
        }
    }

    /// モザイク・ぼかしなど、元画像から計算して図形より下に描くもの。
    public var isEffect: Bool {
        if case .obscure = self { return true }
        return false
    }

    /// 既定の名前に使う表示名。
    public var displayName: String {
        switch self {
        case .arrow: "矢印"
        case .line: "線"
        case .rect: "矩形"
        case .ellipse: "楕円"
        case .text: "テキスト"
        case .obscure(let s): s.mode == .pixelate ? "モザイク" : "ぼかし"
        case .unknown(let type, _): type
        }
    }
}

/// 矢印の頭の形。
public enum ArrowHead: String, Sendable, Codable, CaseIterable {
    /// Skitch 風の先細り。
    case tapered
    /// 線と開いた矢じり。
    case open
}

public struct ArrowSpec: Sendable, Equatable {
    public var from: CGPoint
    public var to: CGPoint
    public var color: RGBAColor
    public var width: Double
    public var head: ArrowHead

    public init(from: CGPoint, to: CGPoint, color: RGBAColor, width: Double, head: ArrowHead = .tapered) {
        self.from = from; self.to = to; self.color = color; self.width = width; self.head = head
    }
}

public struct LineSpec: Sendable, Equatable {
    public var from: CGPoint
    public var to: CGPoint
    public var color: RGBAColor
    public var width: Double

    public init(from: CGPoint, to: CGPoint, color: RGBAColor, width: Double) {
        self.from = from; self.to = to; self.color = color; self.width = width
    }
}

/// 矩形・楕円の共通仕様。
public struct ShapeSpec: Sendable, Equatable {
    public var rect: CGRect
    public var color: RGBAColor
    public var width: Double
    public var fill: RGBAColor?

    public init(rect: CGRect, color: RGBAColor, width: Double, fill: RGBAColor? = nil) {
        self.rect = rect; self.color = color; self.width = width; self.fill = fill
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

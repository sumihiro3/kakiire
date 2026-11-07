// Vector helpers adapted from Sitch (https://github.com/phalladar/Sitch, MIT).
// See THIRD_PARTY_NOTICES.md.
import CoreGraphics

public extension CGPoint {
    static func + (a: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: a.x + v.dx, y: a.y + v.dy) }
    static func - (a: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: a.x - v.dx, y: a.y - v.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}

public extension CGVector {
    var length: CGFloat { (dx * dx + dy * dy).squareRoot() }
    static func * (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }
    static func / (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx / s, dy: v.dy / s) }
    static prefix func - (v: CGVector) -> CGVector { CGVector(dx: -v.dx, dy: -v.dy) }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat { a.dx * b.dx + a.dy * b.dy }
}

public extension CGRect {
    /// 2点を対角とする正規化済みの矩形。
    init(corner a: CGPoint, _ b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// `v` を `lo...hi` に収める。
public func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// 点 `p` から線分 `a`–`b` までの最短距離。
public func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = b - a
    let len2 = CGVector.dot(ab, ab)
    if len2 < 1e-6 { return (p - a).length }
    let t = clamp(CGVector.dot(p - a, ab) / len2, 0, 1)
    return (p - (a + ab * t)).length
}

/// 整数ピクセルの矩形。効果の計算範囲やキャッシュのキーに使う。
public struct PixelRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// `rect` を整数化し、`bounds`(画像サイズ)の内側に切り詰める。空になれば nil。
    public init?(_ rect: CGRect, within size: CGSize) {
        let r = rect.standardized.intersection(CGRect(origin: .zero, size: size))
        if r.isNull { return nil }
        let x0 = Int(r.minX.rounded(.down)), y0 = Int(r.minY.rounded(.down))
        let x1 = Int(r.maxX.rounded(.up)), y1 = Int(r.maxY.rounded(.up))
        guard x1 - x0 >= 1, y1 - y0 >= 1 else { return nil }
        self.init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

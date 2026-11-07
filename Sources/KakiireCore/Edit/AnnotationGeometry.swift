import CoreGraphics
import Foundation

/// 選択中の注釈を変形するつまみ。
public enum Handle: Hashable, Sendable, CaseIterable {
    /// 線・矢印の始点と終点。
    case start, end
    /// 矩形系の四隅と四辺。
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    static let rectHandles: [Handle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
}

public extension Annotation {
    /// 矢印・線のように2点で決まるもの。
    var isTwoPoint: Bool {
        switch content {
        case .arrow, .line: true
        default: false
        }
    }

    /// 描画される範囲(線の太さ・矢じり・白フチを含む)。再描画範囲と範囲選択に使う。
    var bounds: CGRect {
        switch content {
        case .arrow(let a):
            let pad = CGFloat(a.width) * 2 + 4
            return CGRect(corner: a.from, a.to).insetBy(dx: -pad, dy: -pad)
        case .line(let l):
            let pad = CGFloat(l.width) / 2 + 2
            return CGRect(corner: l.from, l.to).insetBy(dx: -pad, dy: -pad)
        case .rect(let s), .ellipse(let s):
            let pad = CGFloat(s.width) / 2 + 1
            return s.rect.standardized.insetBy(dx: -pad, dy: -pad)
        case .text(let t):
            return TextLayout.bounds(t)
        case .obscure(let o):
            return o.rect.standardized
        case .unknown:
            return .null
        }
    }

    /// 平行移動したコピー。
    func moved(by v: CGVector) -> Annotation {
        switch content {
        case .arrow(var a): a.from = a.from + v; a.to = a.to + v; return with(content: .arrow(a))
        case .line(var l): l.from = l.from + v; l.to = l.to + v; return with(content: .line(l))
        case .rect(var s): s.rect = s.rect.offsetBy(dx: v.dx, dy: v.dy); return with(content: .rect(s))
        case .ellipse(var s): s.rect = s.rect.offsetBy(dx: v.dx, dy: v.dy); return with(content: .ellipse(s))
        case .text(var t): t.origin = t.origin + v; return with(content: .text(t))
        case .obscure(var o): o.rect = o.rect.offsetBy(dx: v.dx, dy: v.dy); return with(content: .obscure(o))
        case .unknown: return self
        }
    }

    /// 変形用のつまみと、その位置。テキストは文字サイズで大きさを変えるのでつまみを出さない。
    var handles: [(Handle, CGPoint)] {
        switch content {
        case .arrow(let a): return [(.start, a.from), (.end, a.to)]
        case .line(let l): return [(.start, l.from), (.end, l.to)]
        case .rect(let s), .ellipse(let s): return Self.rectHandlePoints(s.rect)
        case .obscure(let o): return Self.rectHandlePoints(o.rect)
        case .text, .unknown: return []
        }
    }

    /// つまみを `p` まで動かしたコピー。`constrain`(Shift)なら線は 45° 刻み、矩形は正方形。
    func resized(_ handle: Handle, to p: CGPoint, constrain: Bool = false) -> Annotation {
        switch content {
        case .arrow(var a):
            if handle == .start { a.from = constrain ? Self.snap45(p, around: a.to) : p }
            if handle == .end { a.to = constrain ? Self.snap45(p, around: a.from) : p }
            return with(content: .arrow(a))
        case .line(var l):
            if handle == .start { l.from = constrain ? Self.snap45(p, around: l.to) : p }
            if handle == .end { l.to = constrain ? Self.snap45(p, around: l.from) : p }
            return with(content: .line(l))
        case .rect(var s):
            s.rect = Self.resize(s.rect, handle, p, constrain); return with(content: .rect(s))
        case .ellipse(var s):
            s.rect = Self.resize(s.rect, handle, p, constrain); return with(content: .ellipse(s))
        case .obscure(var o):
            o.rect = Self.resize(o.rect, handle, p, constrain); return with(content: .obscure(o))
        case .text, .unknown:
            return self
        }
    }

    /// `p` を `origin` から見て 45° 刻みの方向に寄せる。
    static func snap45(_ p: CGPoint, around origin: CGPoint) -> CGPoint {
        let v = p - origin
        let len = v.length
        if len < 1e-6 { return p }
        let step = Double.pi / 4
        let angle = (atan2(Double(v.dy), Double(v.dx)) / step).rounded() * step
        return CGPoint(x: origin.x + len * CGFloat(cos(angle)), y: origin.y + len * CGFloat(sin(angle)))
    }

    static func rectHandlePoints(_ r: CGRect) -> [(Handle, CGPoint)] {
        let r = r.standardized
        return [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
        ]
    }

    static func resize(_ rect: CGRect, _ h: Handle, _ p: CGPoint, _ constrain: Bool) -> CGRect {
        let r = rect.standardized
        var x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
        switch h {
        case .topLeft: x0 = p.x; y0 = p.y
        case .top: y0 = p.y
        case .topRight: x1 = p.x; y0 = p.y
        case .right: x1 = p.x
        case .bottomRight: x1 = p.x; y1 = p.y
        case .bottom: y1 = p.y
        case .bottomLeft: x0 = p.x; y1 = p.y
        case .left: x0 = p.x
        case .start, .end: break
        }
        var out = CGRect(corner: CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1))
        if constrain, [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(h) {
            // 動かさない側の角を固定して正方形にする。
            let side = max(out.width, out.height)
            let anchorX = (h == .topLeft || h == .bottomLeft) ? r.maxX : r.minX
            let anchorY = (h == .topLeft || h == .topRight) ? r.maxY : r.minY
            let sx: CGFloat = p.x < anchorX ? -1 : 1, sy: CGFloat = p.y < anchorY ? -1 : 1
            out = CGRect(corner: CGPoint(x: anchorX, y: anchorY),
                         CGPoint(x: anchorX + sx * side, y: anchorY + sy * side))
        }
        return out
    }
}

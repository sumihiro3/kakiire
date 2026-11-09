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
        case .highlighter(let p), .pen(let p):
            guard let first = p.points.first else { return .null }
            let r = p.points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            let pad = CGFloat(p.width) / 2 + 2
            return r.insetBy(dx: -pad, dy: -pad)
        case .stamp(let st):
            let r = CGFloat(st.diameter) / 2 + 1
            return CGRect(x: st.center.x - r, y: st.center.y - r, width: r * 2, height: r * 2)
        case .image(let im):
            return im.rect.standardized
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
        case .highlighter(var p): p.points = p.points.map { $0 + v }; return with(content: .highlighter(p))
        case .pen(var p): p.points = p.points.map { $0 + v }; return with(content: .pen(p))
        case .stamp(var st): st.center = st.center + v; return with(content: .stamp(st))
        case .image(var im): im.rect = im.rect.offsetBy(dx: v.dx, dy: v.dy); return with(content: .image(im))
        case .unknown: return self
        }
    }

    /// 変形用のつまみと、その位置。テキストは四隅だけ(大きさは文字サイズで変わる)。
    var handles: [(Handle, CGPoint)] {
        switch content {
        case .arrow(let a): return [(.start, a.from), (.end, a.to)]
        case .line(let l): return [(.start, l.from), (.end, l.to)]
        case .rect(let s), .ellipse(let s): return Self.rectHandlePoints(s.rect)
        case .obscure(let o): return Self.rectHandlePoints(o.rect)
        case .image(let im): return Self.rectHandlePoints(im.rect)
        case .text(let t):
            let b = TextLayout.bounds(t)
            return [(.topLeft, CGPoint(x: b.minX, y: b.minY)), (.topRight, CGPoint(x: b.maxX, y: b.minY)),
                    (.bottomRight, CGPoint(x: b.maxX, y: b.maxY)), (.bottomLeft, CGPoint(x: b.minX, y: b.maxY))]
        case .highlighter, .pen, .stamp, .unknown: return []
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
        case .image(var im):
            // 画像は四隅では縦横比を保つ。Shift で自由に。
            im.rect = Self.resize(im.rect, handle, p, false, keepAspect: !constrain); return with(content: .image(im))
        case .text(let t):
            return with(content: .text(Self.resizeText(t, handle, p)))
        case .highlighter, .pen, .stamp, .unknown:
            return self
        }
    }

    /// 文字サイズの範囲。四隅のつまみで変えるときに収める。
    static let textSizeRange: ClosedRange<Double> = 4...400

    /// つかんだ隅の反対の隅を固定し、`p` までの外形に収まるよう文字サイズを変える。文字は折り返さない。
    static func resizeText(_ t: TextSpec, _ handle: Handle, _ p: CGPoint) -> TextSpec {
        let b = TextLayout.bounds(t)
        guard b.width > 0, b.height > 0 else { return t }
        let fixed: CGPoint
        switch handle {
        case .topLeft: fixed = CGPoint(x: b.maxX, y: b.maxY)
        case .topRight: fixed = CGPoint(x: b.minX, y: b.maxY)
        case .bottomRight: fixed = CGPoint(x: b.minX, y: b.minY)
        case .bottomLeft: fixed = CGPoint(x: b.maxX, y: b.minY)
        default: return t
        }
        let k = min(abs(p.x - fixed.x) / b.width, abs(p.y - fixed.y) / b.height)
        var r = t
        r.fontSize = min(max(t.fontSize * Double(k), textSizeRange.lowerBound), textSizeRange.upperBound)
        let nb = TextLayout.bounds(r)
        // 外形の左上が origin なので、固定した隅から逆算する。
        let left = [.topRight, .bottomRight].contains(handle)
        let top = [.bottomLeft, .bottomRight].contains(handle)
        r.origin = CGPoint(x: left ? fixed.x : fixed.x - nb.width, y: top ? fixed.y : fixed.y - nb.height)
        return r
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

    static func resize(_ rect: CGRect, _ h: Handle, _ p: CGPoint, _ constrain: Bool, keepAspect: Bool = false) -> CGRect {
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
        let isCorner = [Handle.topLeft, .topRight, .bottomRight, .bottomLeft].contains(h)
        if keepAspect, isCorner, r.width > 0, r.height > 0 {
            // 動かさない側の角を固定し、元の縦横比のまま大きい方の比率に合わせる。
            let anchorX = (h == .topLeft || h == .bottomLeft) ? r.maxX : r.minX
            let anchorY = (h == .topLeft || h == .topRight) ? r.maxY : r.minY
            let k = max(abs(p.x - anchorX) / r.width, abs(p.y - anchorY) / r.height)
            let sx: CGFloat = p.x < anchorX ? -1 : 1, sy: CGFloat = p.y < anchorY ? -1 : 1
            return CGRect(corner: CGPoint(x: anchorX, y: anchorY),
                          CGPoint(x: anchorX + sx * r.width * k, y: anchorY + sy * r.height * k))
        }
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

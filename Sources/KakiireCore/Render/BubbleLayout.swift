import CoreGraphics
import Foundation

/// 吹き出しの形と描画。本体は文字の箱を囲むように作り、しっぽと合わせて1つの輪郭にする。
/// 描画・当たり判定・外形はすべてここの輪郭を使う。
public enum BubbleLayout {
    /// 中の文字の箱(白フチなし)。
    public static func textBox(_ b: BubbleSpec) -> CGRect { TextLayout.bounds(b.textSpec) }

    /// 文字と本体の縁のあいだの余白。
    static func margin(_ b: BubbleSpec) -> CGFloat { CGFloat(b.fontSize) * 0.45 }

    /// 輪郭の外に付ける白い縁の太さ。
    public static func edge(_ b: BubbleSpec) -> CGFloat { max(1, CGFloat(b.fontSize) * 0.08) }

    /// 雲・ギザギザ・楕円の土台になる楕円。文字の箱(と余白)が内接する大きさ。
    static func baseEllipse(_ b: BubbleSpec) -> CGRect {
        let m = margin(b)
        let inner = textBox(b).insetBy(dx: -m * 0.5, dy: -m * 0.3)
        let k = CGFloat(2).squareRoot()
        return CGRect(x: inner.midX - inner.width * k / 2, y: inner.midY - inner.height * k / 2,
                      width: inner.width * k, height: inner.height * k)
    }

    /// しっぽを含まない本体の輪郭。
    public static func body(_ b: BubbleSpec) -> CGPath {
        switch b.shape {
        case .rounded:
            let m = margin(b)
            let r = textBox(b).insetBy(dx: -m, dy: -m * 0.7)
            let radius = min(r.width, r.height) * 0.3
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: baseEllipse(b), transform: nil)
        case .cloud:
            return cloud(baseEllipse(b), bump: CGFloat(b.fontSize) * 1.4)
        case .shout:
            return shout(baseEllipse(b), spike: CGFloat(b.fontSize) * 0.55, step: CGFloat(b.fontSize) * 1.1)
        }
    }

    /// 本体の外形(しっぽと白い縁を含まない)。四隅のつまみと整列に使う。
    public static func bodyRect(_ b: BubbleSpec) -> CGRect { body(b).boundingBoxOfPath }

    /// 本体としっぽを合わせた輪郭。しっぽの先が本体の中にあるときは本体だけ。
    public static func outline(_ b: BubbleSpec) -> CGPath {
        let base = body(b)
        guard !base.contains(b.tail) else { return base }
        let c = bodyRect(b).center
        let v = b.tail - c
        let len = v.length
        guard len > 1e-6 else { return base }
        let u = CGVector(dx: v.dx / len, dy: v.dy / len)

        if b.shape == .cloud {
            // 本体の縁から先へ向かって小さくなる丸を3つ並べる(考えている感じ)。
            let exit = exitPoint(base, from: c, to: b.tail)
            let r0 = CGFloat(b.fontSize) * 0.32
            let path = CGMutablePath()
            path.addPath(base)
            for (f, k) in [(0.3, 1.0), (0.66, 0.72), (1.0, 0.48)] as [(CGFloat, CGFloat)] {
                let p = exit + (b.tail - exit) * f
                let r = r0 * k
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            return path
        }

        // 本体の中心から先まで伸ばした三角形。根元は中心にあるので、本体と合わせると縁から生えて見える。
        let w = CGFloat(b.fontSize) * 0.9
        let n = CGVector(dx: -u.dy * w / 2, dy: u.dx * w / 2)
        let tail = CGMutablePath()
        tail.move(to: c + n)
        tail.addLine(to: b.tail)
        tail.addLine(to: c - n)
        tail.closeSubpath()
        return base.union(tail)
    }

    /// 描かれる範囲(しっぽと白い縁を含む)。
    public static func bounds(_ b: BubbleSpec) -> CGRect {
        let e = edge(b) + 1
        return outline(b).boundingBoxOfPath.insetBy(dx: -e, dy: -e)
    }

    /// `p` が吹き出しの上か(輪郭の中、または輪郭から `tolerance` 以内)。
    public static func hits(_ b: BubbleSpec, _ p: CGPoint, tolerance: CGFloat) -> Bool {
        let o = outline(b)
        if o.contains(p) { return true }
        let reach = (edge(b) + tolerance) * 2
        return o.copy(strokingWithWidth: reach, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(p)
    }

    /// 白い縁 → 塗り → 文字の順に描く(y 下向きの context)。`drawsText` を外すと文字だけ描かない
    /// (App で文字を入力している間、入力欄の下に吹き出しだけを見せる)。
    public static func draw(_ b: BubbleSpec, in ctx: CGContext, drawsText: Bool = true) {
        let o = outline(b)
        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.addPath(o)
        ctx.setStrokeColor((b.color == .white ? RGBAColor.black : RGBAColor.white).cgColor)
        ctx.setLineWidth(edge(b) * 2)
        ctx.strokePath()
        ctx.addPath(o)
        ctx.setFillColor(b.color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        if drawsText { TextLayout.draw(b.textSpec, in: ctx) }
    }

    /// `from`(本体の中)から `to` へ進んで、本体を出るところ。
    static func exitPoint(_ body: CGPath, from: CGPoint, to: CGPoint) -> CGPoint {
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if body.contains(from + (to - from) * mid) { lo = mid } else { hi = mid }
        }
        return from + (to - from) * hi
    }

    /// 楕円の周上の点(角度 `t`)と、外向きの向き。
    static func ellipsePoint(_ r: CGRect, _ t: CGFloat) -> (CGPoint, CGVector) {
        let a = r.width / 2, b = r.height / 2
        let p = CGPoint(x: r.midX + a * cos(t), y: r.midY + b * sin(t))
        let n = CGVector(dx: cos(t) / max(a, 1e-6), dy: sin(t) / max(b, 1e-6))
        let len = n.length
        return (p, CGVector(dx: n.dx / len, dy: n.dy / len))
    }

    /// 楕円の周の長さ(Ramanujan の近似)。
    static func perimeter(_ r: CGRect) -> CGFloat {
        let a = r.width / 2, b = r.height / 2
        return .pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
    }

    /// 楕円の周を同じ長さに `count` 等分する角度(`count + 1` 個、最後は 2π)。
    /// 角度で等分すると、横長の楕円の両端で間隔が詰まり、山やトゲの大きさがそろわない。
    static func evenAngles(_ r: CGRect, count: Int) -> [CGFloat] {
        let samples = 720
        var lengths: [CGFloat] = [0]
        var prev = ellipsePoint(r, 0).0
        for i in 1...samples {
            let p = ellipsePoint(r, CGFloat(i) / CGFloat(samples) * 2 * .pi).0
            lengths.append(lengths[i - 1] + (p - prev).length)
            prev = p
        }
        let total = lengths[samples]
        var out: [CGFloat] = [], j = 0
        for k in 0...count {
            let target = total * CGFloat(k) / CGFloat(count)
            while j < samples, lengths[j + 1] < target { j += 1 }
            let seg = max(lengths[min(j + 1, samples)] - lengths[j], 1e-9)
            let f = min(max((target - lengths[j]) / seg, 0), 1)
            out.append((CGFloat(j) + f) / CGFloat(samples) * 2 * .pi)
        }
        return out
    }

    /// 楕円の周に、外へふくらむ山を並べた雲の形。山の幅はおよそ `bump`。
    static func cloud(_ r: CGRect, bump: CGFloat) -> CGPath {
        let count = max(8, Int((perimeter(r) / bump).rounded()))
        let path = CGMutablePath()
        let angles = evenAngles(r, count: count * 2)
        let pts = (0..<count).map { ellipsePoint(r, angles[$0 * 2]) }
        path.move(to: pts[0].0)
        for i in 0..<count {
            let (p, _) = pts[i], (q, _) = pts[(i + 1) % count]
            let (_, n) = ellipsePoint(r, angles[i * 2 + 1])
            let k = (q - p).length * 0.7
            path.addCurve(to: q, control1: p + n * k, control2: q + n * k)
        }
        path.closeSubpath()
        return path
    }

    /// 楕円の周に、外向きのトゲを並べたギザギザの形。トゲの間隔はおよそ `step`、高さは `spike`。
    static func shout(_ r: CGRect, spike: CGFloat, step: CGFloat) -> CGPath {
        let count = max(10, Int((perimeter(r) / step).rounded()))
        let path = CGMutablePath()
        let angles = evenAngles(r, count: count * 2)
        for i in 0..<(count * 2) {
            let (p, n) = ellipsePoint(r, angles[i])
            let q = i % 2 == 0 ? p : p + n * spike
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }
}

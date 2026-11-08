// Tapered arrow geometry adapted from Sitch (https://github.com/phalladar/Sitch, MIT).
// See THIRD_PARTY_NOTICES.md.
import CoreGraphics

/// 矢印の形を作る。A = 始点(尾)、B = 終点(先端)。
public enum ArrowPath {
    struct Frame {
        let dir: CGVector, perp: CGVector, len: CGFloat, w: CGFloat, headLen: CGFloat, headHalf: CGFloat
    }

    static func frame(_ a: CGPoint, _ b: CGPoint, width: Double) -> Frame? {
        let v = b - a
        let len = v.length
        if len < 2 { return nil }
        let dir = v / len
        let w = max(2, CGFloat(width))
        // 矢じりは長さに比例させつつ、線の太さで上下限を決める(短い矢印でも頭が潰れない)。
        let headLen = clamp(len * 0.30, max(10, w * 1.1), w * 3.4)
        return Frame(dir: dir, perp: CGVector(dx: -dir.dy, dy: dir.dx), len: len, w: w,
                     headLen: headLen, headHalf: headLen * 0.42)
    }

    /// Skitch 風の先細り矢印(塗りつぶす閉じたパス)。尾が最も太く、内側に反った側面で細い首へ絞り、
    /// 少し後ろに返した矢じりへつなぐ。
    public static func tapered(from a: CGPoint, to b: CGPoint, width: Double) -> CGPath? {
        guard let f = frame(a, b, width: width) else { return nil }
        let tailHalf = f.w * 0.5
        let neck = max(1.4, f.w * 0.17)
        let headBase = b - f.dir * f.headLen
        let barbBack = headBase - f.dir * (f.headLen * 0.10)
        // 制御点を背骨の近くに置くと、側面が膨らまず内側に反る。
        let ctrlBase = a + (headBase - a) * 0.58
        let ctrlOff = neck + (tailHalf - neck) * 0.22

        let p = CGMutablePath()
        p.move(to: a + f.perp * tailHalf)
        p.addQuadCurve(to: headBase + f.perp * neck, control: ctrlBase + f.perp * ctrlOff)
        p.addLine(to: barbBack + f.perp * f.headHalf)
        p.addLine(to: b)
        p.addLine(to: barbBack - f.perp * f.headHalf)
        p.addLine(to: headBase - f.perp * neck)
        p.addQuadCurve(to: a - f.perp * tailHalf, control: ctrlBase - f.perp * ctrlOff)
        p.closeSubpath()
        return p
    }

    /// 線と開いた矢じり(線で描くパス)。
    public static func open(from a: CGPoint, to b: CGPoint, width: Double) -> CGPath? {
        guard let f = frame(a, b, width: width) else { return nil }
        let back = b - f.dir * f.headLen
        let half = f.headHalf * 1.2
        let p = CGMutablePath()
        p.move(to: a); p.addLine(to: b)
        p.move(to: back + f.perp * half); p.addLine(to: b); p.addLine(to: back - f.perp * half)
        return p
    }

    /// 破線の矢印の部品:軸の終わり(矢じりの付け根)と、開いた矢じり(線で描くパス)。
    /// 軸を付け根で止めるので、破線の切れ目が先端に出ない。
    public static func dashedParts(from a: CGPoint, to b: CGPoint, width: Double) -> (shaftEnd: CGPoint, head: CGPath)? {
        guard let f = frame(a, b, width: width) else { return nil }
        let back = b - f.dir * f.headLen
        let half = f.headHalf * 1.2
        let p = CGMutablePath()
        p.move(to: back + f.perp * half); p.addLine(to: b); p.addLine(to: back - f.perp * half)
        p.move(to: back); p.addLine(to: b)
        return (back, p)
    }
}

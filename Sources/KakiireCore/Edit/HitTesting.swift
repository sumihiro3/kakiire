import CoreGraphics
import Foundation

/// クリック位置から注釈やつまみを探す。座標は元画像のピクセル座標。
public enum HitTesting {
    /// `p` にある最前面の注釈。非表示・ロック中・未知の種類は対象外。
    /// `tolerance` は画面上の数ポイントをピクセルに換算した値を渡す。
    public static func annotation(at p: CGPoint, in doc: Document, tolerance: CGFloat) -> UUID? {
        for a in doc.annotations.reversed() where !a.hidden && !a.locked && hits(a, p, tolerance) {
            return a.id
        }
        return nil
    }

    /// 選択中の注釈のつまみ。
    public static func handle(at p: CGPoint, of a: Annotation, tolerance: CGFloat) -> Handle? {
        a.handles.first { (_, pt) in (p - pt).length <= tolerance }?.0
    }

    /// 範囲選択:外形が `rect` と重なる注釈。
    public static func annotations(intersecting rect: CGRect, in doc: Document) -> [UUID] {
        let r = rect.standardized
        return doc.annotations.filter { !$0.hidden && !$0.locked && $0.bounds.intersects(r) }.map(\.id)
    }

    static func hits(_ a: Annotation, _ p: CGPoint, _ tol: CGFloat) -> Bool {
        switch a.content {
        case .arrow(let s):
            return distanceToSegment(p, s.from, s.to) <= CGFloat(s.width) + tol
        case .line(let s):
            return distanceToSegment(p, s.from, s.to) <= CGFloat(s.width) / 2 + tol
        case .rect(let s):
            let r = s.rect.standardized
            if s.fill != nil { return r.insetBy(dx: -tol, dy: -tol).contains(p) }
            let reach = CGFloat(s.width) / 2 + tol
            return r.insetBy(dx: -reach, dy: -reach).contains(p) && !r.insetBy(dx: reach, dy: reach).contains(p)
        case .ellipse(let s):
            let r = s.rect.standardized
            guard r.width > 0, r.height > 0 else { return false }
            let reach = CGFloat(s.width) / 2 + tol
            // 楕円の外周からの距離を、半径方向の正規化で近似する。
            let dx = (p.x - r.midX) / (r.width / 2), dy = (p.y - r.midY) / (r.height / 2)
            let d = (dx * dx + dy * dy).squareRoot()
            let radial = abs(d - 1) * min(r.width, r.height) / 2
            return s.fill != nil ? d <= 1 + reach / (min(r.width, r.height) / 2) : radial <= reach
        case .text:
            return a.bounds.insetBy(dx: -tol, dy: -tol).contains(p)
        case .obscure(let s):
            return s.rect.standardized.insetBy(dx: -tol, dy: -tol).contains(p)
        case .unknown:
            return false
        }
    }
}

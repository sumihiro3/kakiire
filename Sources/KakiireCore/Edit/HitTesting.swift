import CoreGraphics
import Foundation

/// クリック位置から注釈やつまみを探す。座標は元画像のピクセル座標。
public enum HitTesting {
    /// `p` にある最前面の注釈。非表示・ロック中・未知の種類は対象外。
    /// 描く順はグループが優先するので、配列の順ではなくレイヤーの行の順(前面から)で調べる。
    /// `tolerance` は画面上の数ポイントをピクセルに換算した値を渡す。
    /// `filter` を渡すと、それを満たす注釈だけを調べる(満たさない注釈は手前にあっても飛ばす)。
    public static func annotation(at p: CGPoint, in doc: Document, tolerance: CGFloat,
                                  where filter: (Annotation) -> Bool = { _ in true }) -> UUID? {
        for id in LayerList.rows(doc) {
            guard let a = doc.annotation(id), !a.hidden, !a.locked, filter(a), hits(a, p, tolerance) else { continue }
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
            return distanceToSegment(p, s.from, s.to) <= CGFloat(s.width) + s.outlineBand + tol
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
        case .highlighter(let s), .pen(let s):
            let reach = CGFloat(s.width) / 2 + tol
            guard let first = s.points.first else { return false }
            if s.points.count == 1 { return (p - first).length <= reach }
            return zip(s.points, s.points.dropFirst()).contains { distanceToSegment(p, $0, $1) <= reach }
        case .stamp(let s):
            return (p - s.center).length <= CGFloat(s.diameter) / 2 + tol
        case .image(let s):
            return s.rect.standardized.insetBy(dx: -tol, dy: -tol).contains(p)
        case .unknown:
            return false
        }
    }
}

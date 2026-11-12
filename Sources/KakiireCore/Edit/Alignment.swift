import CoreGraphics
import Foundation

/// 揃える辺・中心線。座標は y 下向きなので `top` は minY。
public enum Alignment: Int, Sendable, CaseIterable {
    case left, centerX, right, top, centerY, bottom
}

/// 等間隔に並べる向き。
public enum Distribution: Int, Sendable, CaseIterable {
    case horizontal, vertical
}

public extension Annotation {
    /// 整列に使う形そのものの外形。線の太さ・矢じり・影などの余白は含めない(ADR 0009)。
    var frame: CGRect {
        switch content {
        case .arrow(let a): return CGRect(corner: a.from, a.to)
        case .line(let l): return CGRect(corner: l.from, l.to)
        case .rect(let s), .ellipse(let s): return s.rect.standardized
        case .obscure(let o): return o.rect.standardized
        case .image(let im): return im.rect.standardized
        case .text(let t): return TextLayout.bounds(t)
        case .stamp(let st):
            let r = CGFloat(st.diameter) / 2
            return CGRect(x: st.center.x - r, y: st.center.y - r, width: r * 2, height: r * 2)
        case .highlighter(let p), .pen(let p):
            guard let first = p.points.first else { return .null }
            return p.points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .unknown:
            return .null
        }
    }
}

/// 複数の注釈の整列・等間隔配置。結果は `.move` の列で、まとめて適用すれば Undo 1回分になる。
///
/// 非表示と形を持たないものは対象外。ロックされたものは動かさないが、基準の範囲には含める(固定した注釈に揃えられる)。
public enum Arrange {
    /// 選択の外形を合わせた範囲の辺・中心に揃える。対象が2つ未満なら空。
    public static func align(_ ids: Set<UUID>, _ alignment: Alignment, in doc: Document) -> [EditOperation] {
        let items = targets(ids, in: doc)
        guard items.count >= 2 else { return [] }
        let all = items.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return items.compactMap { a in
            let f = a.frame
            let v: CGVector
            switch alignment {
            case .left: v = CGVector(dx: all.minX - f.minX, dy: 0)
            case .centerX: v = CGVector(dx: all.midX - f.midX, dy: 0)
            case .right: v = CGVector(dx: all.maxX - f.maxX, dy: 0)
            case .top: v = CGVector(dx: 0, dy: all.minY - f.minY)
            case .centerY: v = CGVector(dx: 0, dy: all.midY - f.midY)
            case .bottom: v = CGVector(dx: 0, dy: all.maxY - f.maxY)
            }
            return move(a, v)
        }
    }

    /// 両端の2つを固定し、隣どうしの隙間(外形の辺の間)を等しくする。対象が3つ未満なら空。
    /// 隙間が負(重なっている)でもそのまま等分する。
    public static func distribute(_ ids: Set<UUID>, _ distribution: Distribution, in doc: Document) -> [EditOperation] {
        let horizontal = distribution == .horizontal
        let lo: (CGRect) -> CGFloat = { horizontal ? $0.minX : $0.minY }
        let size: (CGRect) -> CGFloat = { horizontal ? $0.width : $0.height }
        let items = targets(ids, in: doc).sorted { lo($0.frame) < lo($1.frame) }
        guard items.count >= 3, let first = items.first?.frame, let last = items.last?.frame else { return [] }
        let span = lo(last) + size(last) - lo(first)
        let gap = (span - items.map { size($0.frame) }.reduce(0, +)) / CGFloat(items.count - 1)
        var cursor = lo(first)
        var ops: [EditOperation] = []
        for a in items {
            let f = a.frame
            let d = cursor - lo(f)
            if let op = move(a, horizontal ? CGVector(dx: d, dy: 0) : CGVector(dx: 0, dy: d)) { ops.append(op) }
            cursor += size(f) + gap
        }
        return ops
    }

    /// 注釈の配列の順(背面から)で返す。
    private static func targets(_ ids: Set<UUID>, in doc: Document) -> [Annotation] {
        doc.annotations.filter { ids.contains($0.id) && !$0.hidden && !$0.frame.isNull }
    }

    /// ロックされたもの・動かないもの(誤差程度)は操作にしない。
    private static func move(_ a: Annotation, _ v: CGVector) -> EditOperation? {
        guard !a.locked, abs(v.dx) > 1e-9 || abs(v.dy) > 1e-9 else { return nil }
        return .move([a.id], by: v)
    }
}

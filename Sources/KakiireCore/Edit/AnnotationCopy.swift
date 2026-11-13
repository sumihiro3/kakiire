import CoreGraphics
import Foundation

/// 注釈の複製・コピー&ペースト。クリップボードの読み書きは App / IO が受け持ち、ここは置き方だけを決める。
public enum AnnotationCopy {
    /// コピーの対象。重なり順(背面から)に並べ、中身の分からない注釈は除く。
    public static func copyable(_ ids: Set<UUID>, in doc: Document) -> [Annotation] {
        doc.annotations.filter { ids.contains($0.id) && !$0.content.isUnknown }
    }

    /// `items` を新しい id・名前で `doc` に足す操作と、足した注釈の id(`items` と同じ順)。
    ///
    /// 置き場所は次の順で決める。
    /// - `center` があれば、全体の中心をそこに合わせる(右クリックの「ここにペースト」)。
    /// - なければ元の位置に置く。同じ中身が同じ場所にあれば(複製・同じ文書へのペースト)`step` ずつ右下へずらす。
    /// - それでも `visible` に少しもかからなければ、`visible` の中央へ動かす(別の大きさの文書へのペースト)。
    ///
    /// 足した注釈は表示・ロック解除の状態にする。`label` は既定の名前に使う種類の表示名。
    public static func paste(_ items: [Annotation], into doc: Document, step: CGFloat, center: CGPoint? = nil,
                             visible: CGRect? = nil, label: (AnnotationContent) -> String) -> (ops: [EditOperation], ids: [UUID]) {
        let items = items.filter { !$0.content.isUnknown }
        guard !items.isEmpty else { return ([], []) }
        let box = items.map(\.bounds).filter { !$0.isNull }.reduce(CGRect.null) { $0.union($1) }
        let v = offset(items, box: box, in: doc, step: step, center: center, visible: visible)

        var d = doc, ops: [EditOperation] = [], ids: [UUID] = []
        for item in items {
            let moved = item.moved(by: v)
            let a = Annotation(name: d.nextName(for: moved.content, label: label(moved.content)), content: moved.content)
            let op = EditOperation.add(a)
            ops.append(op); ids.append(a.id)
            d = d.applying(op)
        }
        return (ops, ids)
    }

    private static func offset(_ items: [Annotation], box: CGRect, in doc: Document, step: CGFloat,
                               center: CGPoint?, visible: CGRect?) -> CGVector {
        guard !box.isNull else { return .zero }
        if let center {
            return CGVector(dx: (center.x - box.midX).rounded(), dy: (center.y - box.midY).rounded())
        }
        let existing = doc.annotations.map(\.content)
        func collides(_ v: CGVector) -> Bool {
            items.contains { item in existing.contains(item.moved(by: v).content) }
        }
        var v = CGVector.zero
        // 何度ペーストしても止まるよう上限を置く。
        for k in 0..<100 {
            v = CGVector(dx: step * CGFloat(k), dy: step * CGFloat(k))
            if !collides(v) { break }
        }
        if let visible, !visible.isNull, !visible.isEmpty, !box.offsetBy(dx: v.dx, dy: v.dy).intersects(visible) {
            v = CGVector(dx: (visible.midX - box.midX).rounded(), dy: (visible.midY - box.midY).rounded())
        }
        return v
    }
}

extension AnnotationContent {
    var isUnknown: Bool { if case .unknown = self { true } else { false } }
}

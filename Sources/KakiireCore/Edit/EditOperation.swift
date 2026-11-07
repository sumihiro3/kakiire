import CoreGraphics
import Foundation

/// App 層から文書に加える変更。文書はこれを通してだけ書き換える。
public enum EditOperation: Sendable, Equatable {
    /// 注釈を追加する。`index` が nil なら最前面。
    case add(Annotation, index: Int? = nil)
    case remove(Set<UUID>)
    /// ロックされていないものだけを平行移動する。
    case move(Set<UUID>, by: CGVector)
    /// 同じ id の注釈を差し替える(形・スタイル・文字の変更はすべてこれ)。
    case replace(Annotation)
    /// 重なり順を変える。`index` は移動後の位置。
    case reorder(UUID, to: Int)
    case setHidden(Set<UUID>, Bool)
    case setLocked(Set<UUID>, Bool)
    case rename(UUID, String)
    /// 元画像を差し替える。注釈は残し、切り抜きは解除する。
    case replaceBase(ImageAsset)
}

public extension Document {
    /// 変更を適用した新しい文書を返す。存在しない id への操作は無視する。
    func applying(_ op: EditOperation) -> Document {
        var d = self
        switch op {
        case .add(let a, let index):
            let i = index.map { clamp($0, 0, d.annotations.count) } ?? d.annotations.count
            d.annotations.insert(a, at: i)
        case .remove(let ids):
            d.annotations.removeAll { ids.contains($0.id) }
        case .move(let ids, let v):
            d.annotations = d.annotations.map { ids.contains($0.id) && !$0.locked ? $0.moved(by: v) : $0 }
        case .replace(let a):
            if let i = d.annotations.firstIndex(where: { $0.id == a.id }) { d.annotations[i] = a }
        case .reorder(let id, let to):
            if let i = d.annotations.firstIndex(where: { $0.id == id }) {
                let a = d.annotations.remove(at: i)
                d.annotations.insert(a, at: clamp(to, 0, d.annotations.count))
            }
        case .setHidden(let ids, let v):
            for i in d.annotations.indices where ids.contains(d.annotations[i].id) { d.annotations[i].hidden = v }
        case .setLocked(let ids, let v):
            for i in d.annotations.indices where ids.contains(d.annotations[i].id) { d.annotations[i].locked = v }
        case .rename(let id, let name):
            if let i = d.annotations.firstIndex(where: { $0.id == id }) { d.annotations[i].name = name }
        case .replaceBase(let asset):
            d.base = BaseImage(asset: asset)
            d.canvas.crop = nil
        }
        return d
    }

    func applying(_ ops: [EditOperation]) -> Document {
        ops.reduce(self) { $0.applying($1) }
    }
}

/// ドラッグのような連続した変更を、1回の Undo にまとめる。
///
/// 開始時の文書を `before` に保持し、`update` のたびに `before` から計算し直す。
/// 操作には「開始時からの累計」(移動量の合計など)を渡す。
public struct EditSession: Sendable {
    public let before: Document
    public private(set) var current: Document

    public init(_ document: Document) {
        before = document
        current = document
    }

    /// 開始時の文書に `ops` を適用した状態にする。
    public mutating func update(_ ops: [EditOperation]) {
        current = before.applying(ops)
    }

    public mutating func update(_ op: EditOperation) { update([op]) }

    /// 変更があれば `(before, after)` を返す。変化がなければ nil(Undo を積まない)。
    public func commit() -> (before: Document, after: Document)? {
        current == before ? nil : (before, current)
    }
}

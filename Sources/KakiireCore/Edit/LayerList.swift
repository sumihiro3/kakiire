import Foundation

/// レイヤーパネルの行と、注釈の配列(先頭が最背面)との対応。
///
/// パネルは上から「図形 → ハイライター → 効果 → 画像」のグループ順で、各グループの中は前面が上。
/// 描く順はグループが優先するので、グループをまたぐ並べ替えは意味がなく、させない。
public enum LayerList {
    /// パネルの上から順の id。
    public static func rows(_ doc: Document) -> [UUID] {
        RenderGroup.allCases.reversed().flatMap { g in
            doc.annotations.reversed().filter { $0.content.renderGroup == g }.map(\.id)
        }
    }

    /// 行 `id` を、パネルの挿入位置 `row`(0...行数。NSTableView のドロップ位置と同じ数え方)へ動かす操作。
    /// 別のグループへ入る位置や、動かない場合は nil。
    public static func move(_ id: UUID, toRow row: Int, in doc: Document) -> EditOperation? {
        let ids = rows(doc)
        guard let from = ids.firstIndex(of: id), let a = doc.annotation(id) else { return nil }
        let group = a.content.renderGroup
        let groupRows = ids.indices.filter { doc.annotation(ids[$0])?.content.renderGroup == group }
        guard let first = groupRows.first, let last = groupRows.last, (first...(last + 1)).contains(row) else { return nil }
        let target = row > from ? row - 1 : row
        guard target != from else { return nil }

        // グループ内の新しい並び(パネル順 = 前面が先)を作り、配列でグループが占める位置に背面から詰め直す。
        var order = groupRows.map { ids[$0] }
        order.remove(at: from - first)
        order.insert(id, at: target - first)
        let slots = doc.annotations.indices.filter { doc.annotations[$0].content.renderGroup == group }
        var arranged = doc.annotations
        for (slot, member) in zip(slots, order.reversed()) { arranged[slot] = doc.annotation(member)! }
        guard let to = arranged.firstIndex(where: { $0.id == id }) else { return nil }
        return .reorder(id, to: to)
    }

    /// グループの中で最前面・最背面へ。
    public static func moveToFront(_ id: UUID, in doc: Document) -> EditOperation? {
        guard let g = doc.annotation(id)?.content.renderGroup,
              let first = rows(doc).firstIndex(where: { doc.annotation($0)?.content.renderGroup == g }) else { return nil }
        return move(id, toRow: first, in: doc)
    }

    public static func moveToBack(_ id: UUID, in doc: Document) -> EditOperation? {
        let ids = rows(doc)
        guard let g = doc.annotation(id)?.content.renderGroup,
              let last = ids.lastIndex(where: { doc.annotation($0)?.content.renderGroup == g }) else { return nil }
        return move(id, toRow: last + 1, in: doc)
    }
}

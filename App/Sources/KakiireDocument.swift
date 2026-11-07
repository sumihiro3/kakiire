import AppKit
import KakiireCore
import KakiireIO

/// 編集中の1枚。中身(`content`)は Core の値型で、変更は `setContent` だけを通す。
///
/// フェーズ1は `.kakiire` 保存がないため、NSDocument の保存の仕組みは使わない。
/// 閉じる・終了の確認は「書き出していない変更」で独自に出す。
final class KakiireDocument: NSDocument {
    private(set) var content: Document
    let sourceName: String
    /// 最後に書き出し・コピーしてから変更があるか。
    private(set) var hasUnexportedChanges = false
    /// 中身が変わったとき(Undo/Redo を含む)に呼ばれる。引数は (変更前, 変更後)。
    var onChange: ((Document, Document) -> Void)?

    init(asset: ImageAsset, sourceName: String) {
        content = Document(base: BaseImage(asset: asset))
        self.sourceName = sourceName
        super.init()
    }

    nonisolated override class var autosavesInPlace: Bool { false }

    override var displayName: String! {
        get { fileURL == nil ? sourceName : super.displayName }
        set { super.displayName = newValue }
    }

    // 保存しない文書なので、NSDocument の「保存しますか？」は出さない。
    override var isDocumentEdited: Bool { false }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(document: self))
        WelcomeWindowController.shared.closeIfOpen()
    }

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [
            NSLocalizedDescriptionKey: "この版では編集用ファイルの保存に対応していません。書き出しを使ってください。",
        ])
    }

    /// 中身を差し替え、元に戻せるよう Undo に積む。
    func setContent(_ new: Document, actionName: String) {
        let old = content
        guard old != new else { return }
        content = new
        hasUnexportedChanges = true
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.setContent(old, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
        onChange?(old, new)
    }

    func markExported() { hasUnexportedChanges = false }
}

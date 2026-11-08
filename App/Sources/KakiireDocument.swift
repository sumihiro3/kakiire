import AppKit
import KakiireCore
import KakiireIO
import UniformTypeIdentifiers

extension UTType {
    /// 編集用ファイル `.kakiire`。Info.plist の UTExportedTypeDeclarations で宣言している。
    nonisolated static let kakiire = UTType(exportedAs: "com.tep-lab.kakiire")
}

/// 編集中の1枚。中身(`content`)は Core の値型で、変更は `setContent` だけを通す。
///
/// 保存・自動保存・版の履歴・「最近使った項目」は NSDocument に任せる。
/// 画像ファイルから作った文書は fileURL を持たない無題文書で、保存時に `.kakiire` を求める。
final class KakiireDocument: NSDocument {
    private(set) var content: Document
    private var manifest: Manifest?
    let sourceName: String
    /// アプリより新しい形式のファイル。表示だけして、編集・保存はさせない。
    private(set) var isReadOnly = false
    /// 中身が変わったとき(Undo/Redo・版の復元を含む)に呼ばれる。引数は (変更前, 変更後)。
    var onChange: ((Document, Document) -> Void)?

    /// 画像から新しい文書を作る。
    init(asset: ImageAsset, sourceName: String) {
        content = Document(base: BaseImage(asset: asset))
        self.sourceName = sourceName
        super.init()
        fileType = UTType.kakiire.identifier
    }

    /// `.kakiire` を開くときに NSDocument が使う。中身は直後の `read` で入る。
    override init() {
        content = Document(base: BaseImage(asset: Self.placeholder))
        sourceName = ""
        super.init()
    }

    private static let placeholder: ImageAsset = {
        let ctx = Renderer.makeContext(width: 1, height: 1)!
        return try! ImageImport.asset(from: ctx.makeImage()!)
    }()

    nonisolated override class var autosavesInPlace: Bool { true }

    override var displayName: String! {
        get {
            let name: String = fileURL == nil && !sourceName.isEmpty ? sourceName : super.displayName
            return isReadOnly ? String(localized: "\(name)(読み取り専用)") : name
        }
        set { super.displayName = newValue }
    }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(document: self))
        WelcomeWindowController.shared.closeIfOpen()
    }

    nonisolated override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [UTType.kakiire.identifier]
    }

    override func data(ofType typeName: String) throws -> Data {
        if isReadOnly {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "新しい版の Kakiire で作られたファイルのため、保存できません。"),
            ])
        }
        let now = Date()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        var m = manifest ?? Manifest(appVersion: appVersion, createdAt: now, updatedAt: now)
        m.formatVersion = KakiireArchive.formatVersion
        m.appVersion = appVersion
        m.updatedAt = now
        let data = try KakiireArchive.write(content, manifest: m)
        manifest = m
        return data
    }

    // 既定(canConcurrentlyReadDocuments = false)ではメインスレッドで呼ばれる。
    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated { try load(data, typeName) }
    }

    private func load(_ data: Data, _ typeName: String) throws {
        let old = content
        if UTType(typeName)?.conforms(to: .kakiire) == true {
            let loaded = try KakiireArchive.read(data)
            content = loaded.document
            manifest = loaded.manifest
            isReadOnly = loaded.isReadOnly
        } else {
            content = Document(base: BaseImage(asset: try ImageImport.asset(from: data)))
        }
        // 版の復元・「元に戻す(最後に保存した状態)」ではウインドウが既にあるので知らせる。
        if old != content { onChange?(old, content) }
    }

    /// 中身を差し替え、元に戻せるよう Undo に積む(変更済みの印と自動保存も Undo から付く)。
    func setContent(_ new: Document, actionName: String) {
        guard !isReadOnly else { NSSound.beep(); return }
        let old = content
        guard old != new else { return }
        content = new
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.setContent(old, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
        onChange?(old, new)
    }
}

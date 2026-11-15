import AppIntents
import AppKit
import KakiireCore
import KakiireIO
import UniformTypeIdentifiers

// 「ショートカット」・Spotlight・Siri から呼べるアクション(ADR 0011)。
// 枠やモザイクを付けるアクションは作らない。座標を入れるのはショートカットの画面では使いにくく、CLI / MCP が受け持つ。

/// 範囲を選んでスクリーンショットを撮り、編集画面で開く。
struct CaptureScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "範囲を撮って Kakiire で開く"
    static let description = IntentDescription("範囲(Space でウインドウ)を選んでスクリーンショットを撮り、編集画面で開きます。")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        // 取り消したときは何もせずに終える(エラーにしない)。
        if let asset = await withCheckedContinuation({ c in ScreenCapture.interactive { c.resume(returning: $0) } }) {
            KakiireDocumentController.current.openNew(asset: asset, name: String(localized: "スクリーンショット"))
        }
        return .result()
    }
}

/// 渡された画像を、無題の文書として編集画面で開く。
struct OpenImageIntent: AppIntent {
    static let title: LocalizedStringResource = "画像を Kakiire で開く"
    static let description = IntentDescription("画像を編集画面で開きます。元の画像ファイルは書き換えません。")
    static let openAppWhenRun = true

    @Parameter(title: "画像", supportedContentTypes: [.image])
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$image) を Kakiire で開く")
    }

    @MainActor func perform() async throws -> some IntentResult {
        let asset = try ImageImport.asset(from: image.data)
        let name = (image.filename as NSString).deletingPathExtension
        KakiireDocumentController.current.openNew(asset: asset, name: name.isEmpty ? String(localized: "画像") : name)
        NSApp.activate()
        return .result()
    }
}

/// `.kakiire` を PNG / JPEG にする。アプリの画面は出さない。
struct ExportDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Kakiire 文書を画像に書き出す"
    static let description = IntentDescription("Kakiire 文書(.kakiire)を PNG か JPEG の画像にします。モザイク・ぼかしは焼き込まれます。")

    @Parameter(title: "Kakiire 文書", supportedContentTypes: [UTType(exportedAs: "com.tep-lab.kakiire")])
    var document: IntentFile

    @Parameter(title: "形式", default: .png)
    var format: ImageFormatEntity

    @Parameter(title: "倍率(%)", description: "省略すると、文書の「画像サイズ」のまま書き出します。", inclusiveRange: (1, 1600))
    var scalePercent: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$document) を \(\.$format) に書き出す") {
            \.$scalePercent
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let data = try ImageExport.data(ofArchive: document.data, format: format.exportFormat,
                                        scale: scalePercent.map { Double($0) / 100 })
        let base = (document.filename as NSString).deletingPathExtension
        let name = (base.isEmpty ? "Kakiire" : base) + "." + format.exportFormat.fileExtension
        return .result(value: IntentFile(data: data, filename: name, type: format.exportFormat.utType))
    }
}

/// 最前面で編集している画像を PNG で渡す。
struct CurrentImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Kakiire で編集中の画像を取得"
    static let description = IntentDescription("Kakiire で最前面の文書を PNG にして渡します。モザイク・ぼかしは焼き込まれます。")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let controller = NSDocumentController.shared
        guard let doc = (controller.currentDocument ?? controller.documents.first) as? KakiireDocument else {
            throw KakiireIntentError.noDocument
        }
        let data = try ImageExport.data(of: doc.content, format: .png)
        return .result(value: IntentFile(data: data, filename: doc.displayName + ".png", type: .png))
    }
}

/// 書き出しの形式。`ExportFormat`(IO)は表示名を持たないので、ここで名前を付ける。
enum ImageFormatEntity: String, AppEnum {
    case png, jpeg

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "形式"
    static let caseDisplayRepresentations: [ImageFormatEntity: DisplayRepresentation] = [
        .png: "PNG",
        .jpeg: "JPEG",
    ]

    var exportFormat: ExportFormat { self == .png ? .png : .jpeg }
}

enum KakiireIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noDocument

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDocument: "Kakiire で開いている画像がありません。"
        }
    }
}

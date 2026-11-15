import Foundation
import KakiireCore
import KakiireIO

// Core / IO は画面の文言を持たない。表示する名前とエラー文はここで表示言語に合わせる。

extension AnnotationContent {
    /// 種類の表示名。既定のレイヤー名(「矢印 1」)にも使い、作ったときの言語のまま文書に残る。
    var localizedName: String {
        switch self {
        case .arrow: String(localized: "矢印")
        case .line: String(localized: "線")
        case .rect: String(localized: "矩形")
        case .ellipse: String(localized: "楕円")
        case .text: String(localized: "テキスト")
        case .bubble: String(localized: "吹き出し")
        case .obscure(let s): s.mode == .pixelate ? String(localized: "モザイク") : String(localized: "ぼかし")
        case .highlighter: String(localized: "ハイライター")
        case .pen: String(localized: "ペン")
        case .stamp: String(localized: "スタンプ")
        case .image: String(localized: "画像")
        case .unknown(let type, _): type
        }
    }
}

extension RenderGroup {
    /// レイヤーパネルの見出し。
    var localizedTitle: String {
        switch self {
        case .image: String(localized: "画像")
        case .effect: String(localized: "モザイク・ぼかし")
        case .highlight: String(localized: "ハイライター")
        case .shape: String(localized: "図形・文字")
        }
    }
}

enum ErrorLocalizer {
    /// IO のエラーを表示言語の文に置き換える。知らないエラーはそのまま返す。
    static func localize(_ error: any Error) -> any Error {
        let message: String?
        switch error {
        case let e as ZipError:
            message = switch e {
            case .notAZip: String(localized: "zip 形式ではありません。")
            case .unsupported(let s): String(localized: "対応していない zip です(\(s))。")
            case .corrupted(let s): String(localized: "ファイルが壊れています(\(s))。")
            case .unsafePath(let s): String(localized: "不正なパスを含んでいます(\(s))。")
            }
        case let e as KakiireArchiveError:
            message = switch e {
            case .missing(let name): String(localized: "必要なファイル(\(name))が見つかりません。")
            case .tooNew(let v): String(localized: "新しい版の Kakiire で作られたファイルです(形式 \(v))。アプリを更新してください。")
            }
        case is ImageImportError:
            message = String(localized: "画像を読み込めませんでした。")
        case let e as ImageExportError:
            message = switch e {
            case .renderFailed: String(localized: "画像を描画できませんでした。")
            case .encodeFailed: String(localized: "画像を書き出せませんでした。")
            }
        default:
            message = nil
        }
        guard let message else { return error }
        return NSError(domain: "Kakiire", code: 1, userInfo: [NSLocalizedDescriptionKey: message, NSUnderlyingErrorKey: error])
    }
}

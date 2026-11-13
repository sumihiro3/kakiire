import Foundation
import KakiireCore

public enum AnnotationClipboardError: Error, LocalizedError {
    case tooNew(Int)

    public var errorDescription: String? {
        switch self {
        case .tooNew(let v): "These annotations were copied from a newer version of Kakiire (format \(v))."
        }
    }
}

/// 注釈をクリップボードに載せる書式。別の文書・別のウインドウへも貼れるよう、画像オーバーレイの画像も含める。
///
/// ```
/// { "format": 1,
///   "annotations": [ document.json と同じ形の注釈 ],
///   "assets": { "assets/<sha256>.png": "<PNG の base64>" } }
/// ```
public enum AnnotationClipboard {
    /// 書式の版。互換性を壊す変更のときだけ上げる。
    public static let format = 1
    /// クリップボードの型。アプリの bundle id を前に付ける。
    public static let typeIdentifier = "com.tep-lab.kakiire.annotations"

    struct Payload: Codable {
        var format: Int
        var annotations: [Annotation]
        var assets: [String: Data]
    }

    public static func encode(_ annotations: [Annotation]) throws -> Data {
        var assets: [String: Data] = [:]
        for a in annotations {
            if case .image(let im) = a.content { assets[im.assetPath] = im.asset.data }
        }
        return try JSONEncoder().encode(Payload(format: format, annotations: annotations, assets: assets))
    }

    /// 画像の読めない画像オーバーレイは、文書と同じく中身の分からない注釈になる(貼り付けでは除く)。
    public static func decode(_ data: Data) throws -> [Annotation] {
        struct Header: Decodable { var format: Int }
        let v = try JSONDecoder().decode(Header.self, from: data).format
        guard v <= format else { throw AnnotationClipboardError.tooNew(v) }
        struct Assets: Decodable { var assets: [String: Data] }
        let raw = try JSONDecoder().decode(Assets.self, from: data).assets
        let decoder = JSONDecoder()
        decoder.userInfo[Annotation.assetsUserInfoKey] = raw.compactMapValues { try? ImageImport.asset(from: $0) }
        return try decoder.decode(Payload.self, from: data).annotations
    }
}

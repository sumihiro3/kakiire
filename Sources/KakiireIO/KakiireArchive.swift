import CoreGraphics
import Foundation
import KakiireCore

/// `.kakiire` の manifest.json。
public struct Manifest: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var appVersion: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(formatVersion: Int = KakiireArchive.formatVersion, appVersion: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum KakiireArchiveError: Error, LocalizedError {
    case missing(String)
    case tooNew(Int)

    public var errorDescription: String? {
        switch self {
        case .missing(let name): "必要なファイル(\(name))が見つかりません。"
        case .tooNew(let v): "新しい版の Kakiire で作られたファイルです(形式 \(v))。アプリを更新してください。"
        }
    }
}

/// 編集用ファイル `.kakiire`(実体は zip)の読み書き。
///
/// ```
/// manifest.json   形式バージョン・アプリバージョン・作成/更新日時
/// document.json   キャンバス・画像操作・注釈リスト
/// base.png        元画像(取り込んだときのまま)
/// assets/<sha256>.png  画像オーバーレイの画像(内容で重複を除く)
/// preview.png     焼き込み済みサムネイル(長辺 1024px まで)
/// ```
public enum KakiireArchive {
    /// このアプリが書く形式。互換性を壊す変更のときだけ上げる。
    public static let formatVersion = 1
    public static let previewMaxSide: CGFloat = 1024
    static let baseName = "base.png"

    public struct Loaded: Sendable {
        public let document: Document
        public let manifest: Manifest
        /// アプリより新しい形式。表示はできるが、保存すると情報を落としうるので編集させない。
        public let isReadOnly: Bool
    }

    public static func write(_ doc: Document, manifest: Manifest, cache: RenderCache = RenderCache()) throws -> Data {
        var zip = ZipWriter(date: manifest.updatedAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try zip.add("manifest.json", encoder.encode(manifest), compress: true)
        try zip.add("document.json", encoder.encode(doc.descriptor(baseAssetName: baseName)), compress: true)
        // PNG は圧縮済みなので stored。
        try zip.add(baseName, doc.base.asset.data, compress: false)
        // 参照されている画像だけを書く(Undo で消えた画像は残さない)。
        var written: Set<String> = []
        for a in doc.annotations {
            guard case .image(let im) = a.content, written.insert(im.assetPath).inserted else { continue }
            try zip.add(im.assetPath, im.asset.data, compress: false)
        }
        if let preview = try? previewPNG(doc, cache: cache) {
            try zip.add("preview.png", preview, compress: false)
        }
        return zip.finalize()
    }

    public static func read(_ data: Data) throws -> Loaded {
        let zip = try ZipReader(data)
        // Finder で展開して「フォルダを圧縮」し直すと、全エントリにフォルダ名が付く。manifest.json の階層を基準にする。
        guard let manifestEntry = zip.entries
            .filter({ $0.name == "manifest.json" || $0.name.hasSuffix("/manifest.json") })
            .min(by: { $0.name.count < $1.name.count })
        else { throw KakiireArchiveError.missing("manifest.json") }
        let prefix = String(manifestEntry.name.dropLast("manifest.json".count))

        func entryData(_ name: String) throws -> Data {
            guard let e = zip.entry(named: prefix + name) else { throw KakiireArchiveError.missing(name) }
            return try zip.data(for: e)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: zip.data(for: manifestEntry))
        let tooNew = manifest.formatVersion > formatVersion

        var assets: [String: ImageAsset] = [:]
        for e in zip.entries where e.name.hasPrefix(prefix + "assets/") {
            let name = String(e.name.dropFirst(prefix.count))
            // 壊れた素材があっても文書は開く(その注釈は未知の種類として JSON ごと残る)。
            if let asset = try? ImageImport.asset(from: zip.data(for: e)) { assets[name] = asset }
        }
        decoder.userInfo[Annotation.assetsUserInfoKey] = assets

        let descriptor: DocumentDescriptor
        do {
            descriptor = try decoder.decode(DocumentDescriptor.self, from: entryData("document.json"))
        } catch {
            if tooNew { throw KakiireArchiveError.tooNew(manifest.formatVersion) }
            throw error
        }
        try checkAssetName(descriptor.base.asset)
        let base = try ImageImport.asset(from: entryData(descriptor.base.asset))
        return Loaded(document: Document(descriptor: descriptor, baseAsset: base), manifest: manifest, isReadOnly: tooNew)
    }

    /// document.json から参照されるファイル名に、上位ディレクトリへの参照を許さない。
    static func checkAssetName(_ name: String) throws {
        try ZipReader.checkPath(name)
    }

    /// 書き出しと同じ描画で作る縮小プレビュー。利用者の出力倍率は無視して長辺 1024px に収める。
    public static func previewPNG(_ doc: Document, cache: RenderCache = RenderCache()) throws -> Data {
        var d = doc
        let crop = doc.effectiveCrop
        d.canvas.outputScale = min(1, previewMaxSide / max(crop.width, crop.height, 1))
        guard let img = Renderer.makeImage(d, cache: cache) else { throw ImageExportError.renderFailed }
        return try ImageExport.data(img, format: .png)
    }
}

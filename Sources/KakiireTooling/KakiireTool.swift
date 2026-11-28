import CoreGraphics
import Foundation
import KakiireCore
import KakiireIO

/// CLI と MCP サーバーが返すエラー。文言は英語だけ(ADR 0007)。
public enum ToolError: Error, LocalizedError, Equatable {
    case usage(String)
    case invalidAnnotations(String)
    case unsupportedOutput(String)
    case wouldOverwriteInput(String)
    case readOnly(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let m): m
        case .invalidAnnotations(let m): "Invalid annotations: \(m)"
        case .unsupportedOutput(let p): "Unsupported output extension: \(p) (use .png, .jpg, .jpeg or .kakiire)"
        case .wouldOverwriteInput(let p): "Refusing to overwrite the input file \(p). Pass force to allow it."
        case .readOnly(let p): "\(p) was made by a newer version of Kakiire and cannot be edited."
        }
    }
}

/// 出力の種類。拡張子で決める。
public enum OutputKind: Sendable, Equatable {
    case image(ExportFormat)
    case archive

    public init(url: URL) throws {
        switch url.pathExtension.lowercased() {
        case "png": self = .image(.png)
        case "jpg", "jpeg": self = .image(.jpeg)
        case "kakiire": self = .archive
        default: throw ToolError.unsupportedOutput(url.path)
        }
    }
}

/// `info` の結果。座標・大きさはすべて元画像のピクセル(左上原点・y 下向き)。
public struct DocumentInfo: Encodable, Sendable {
    public var width: Int
    public var height: Int
    /// 切り抜き `[x, y, w, h]`。nil は画像全体。
    public var crop: [Double]?
    public var outputScale: Double
    public var outputWidth: Int
    public var outputHeight: Int
    public var annotations: [Annotation]
    /// 各注釈が描かれる範囲。`annotations` と同じ順。
    public var bounds: [DrawnBounds]
    /// この画像に合う線の太さ・文字の大きさの目安(元画像のピクセル)。
    public var suggested: SuggestedStyle
    /// MCP が返すプレビュー(長辺 1024px)の大きさ。
    public var preview: PreviewSize
}

/// 注釈が描かれる範囲 `[x, y, w, h]`。線の太さ・矢じり・白フチを含む。
public struct DrawnBounds: Encodable, Sendable, Equatable {
    /// 渡した配列(`info` では文書の注釈)の中での位置。
    public var index: Int
    public var type: String
    public var bounds: [Int]
    /// 文字だけの範囲(白フチの余白を除く)。text のときだけ。下線や矢印の位置合わせに使う。
    public var glyphs: [Int]?
}

/// 画像の幅に合わせた大きさの目安。幅 2000px で矢印 16・枠 6・文字 40・スタンプ 56 を基準に比例させる。
public struct SuggestedStyle: Encodable, Sendable, Equatable {
    public var arrowWidth: Int
    public var lineWidth: Int
    public var rectWidth: Int
    public var fontSize: Int
    public var stampDiameter: Int
    public var mosaicStrength: Int

    public init(imageWidth: Double) {
        let k = max(0.25, imageWidth / 2000)
        func v(_ base: Double) -> Int { max(1, Int((base * k).rounded())) }
        arrowWidth = v(16); lineWidth = v(6); rectWidth = v(6); fontSize = v(40); stampDiameter = v(56); mosaicStrength = v(16)
    }
}

public struct PreviewSize: Encodable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// プレビューの1px が元画像の何 px か の逆数。`image_x = crop_x + preview_x / scale`。
    public var scale: Double
}

/// `annotate` の指定。
public struct AnnotateRequest: Sendable {
    public var input: URL
    /// 書き出し先。形式はそれぞれの拡張子で決まる。
    public var outputs: [URL]
    /// document.json の `annotations` と同じ形の JSON 配列。
    public var annotations: Data?
    public var crop: CGRect?
    public var scale: Double?
    public var force: Bool

    public init(input: URL, outputs: [URL], annotations: Data? = nil, crop: CGRect? = nil, scale: Double? = nil, force: Bool = false) {
        self.input = input; self.outputs = outputs; self.annotations = annotations
        self.crop = crop; self.scale = scale; self.force = force
    }

    public init(input: URL, output: URL, annotations: Data? = nil, crop: CGRect? = nil, scale: Double? = nil, force: Bool = false) {
        self.init(input: input, outputs: [output], annotations: annotations, crop: crop, scale: scale, force: force)
    }
}

/// `annotate` の結果。
public struct AnnotateResult: Sendable {
    public var document: Document
    /// この呼び出しで足した注釈(渡した順)。
    public var added: [Annotation]
}

/// CLI と MCP サーバーが共有する処理。
public enum KakiireTool {
    /// `.kakiire` の manifest に書くバージョン。`project.yml` の `MARKETING_VERSION` と合わせる(テストで確かめる)。
    public static let appVersion = "0.11.1"

    /// 入力として受け付ける注釈の `type`。`image` は素材を要するので受け付けない。
    public static let annotationTypes = ["arrow", "line", "rect", "ellipse", "text", "obscure", "highlighter", "pen", "stamp", "bubble"]

    public struct Loaded: Sendable {
        public var document: Document
        public var manifest: Manifest?
        public var isReadOnly: Bool
    }

    /// 画像ファイルか `.kakiire` を読む。
    public static func load(_ url: URL) throws -> Loaded {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "kakiire" {
            let l = try KakiireArchive.read(data)
            return Loaded(document: l.document, manifest: l.manifest, isReadOnly: l.isReadOnly)
        }
        return Loaded(document: Document(base: BaseImage(asset: try ImageImport.asset(from: data))), manifest: nil, isReadOnly: false)
    }

    public static func info(_ doc: Document) -> DocumentInfo {
        let crop = doc.effectiveCrop
        let scale = doc.canvas.outputScale > 0 ? doc.canvas.outputScale : 1
        let pf = min(1, KakiireArchive.previewMaxSide / max(crop.width, crop.height, 1))
        return DocumentInfo(
            width: Int(doc.pixelSize.width), height: Int(doc.pixelSize.height),
            crop: doc.canvas.crop.map { _ in [crop.minX, crop.minY, crop.width, crop.height].map(Double.init) },
            outputScale: scale,
            outputWidth: max(1, Int((crop.width * scale).rounded())),
            outputHeight: max(1, Int((crop.height * scale).rounded())),
            annotations: doc.annotations,
            bounds: drawnBounds(doc.annotations),
            suggested: SuggestedStyle(imageWidth: crop.width),
            preview: PreviewSize(width: max(1, Int((crop.width * pf).rounded())),
                                 height: max(1, Int((crop.height * pf).rounded())), scale: pf))
    }

    /// 注釈ごとの描かれる範囲。描かれないもの(知らない type)は除く。
    public static func drawnBounds(_ annotations: [Annotation]) -> [DrawnBounds] {
        func ints(_ r: CGRect) -> [Int] {
            [r.minX, r.minY, r.width, r.height].map { Int($0.rounded()) }
        }
        return annotations.enumerated().compactMap { i, a in
            let b = a.bounds
            guard !b.isNull, !b.isEmpty else { return nil }
            var glyphs: [Int]?
            if case .text(let t) = a.content {
                let pad = TextLayout.padding(t)
                glyphs = ints(b.insetBy(dx: pad, dy: pad))
            } else if case .bubble(let s) = a.content {
                let pad = TextLayout.padding(s.textSpec)
                glyphs = ints(BubbleLayout.textBox(s).insetBy(dx: pad, dy: pad))
            }
            return DrawnBounds(index: i, type: a.content.typeName, bounds: ints(b), glyphs: glyphs)
        }
    }

    /// `pretty` を外すと1行で返す(MCP ではエージェントの文脈を節約するため)。
    public static func infoJSON(_ doc: Document, pretty: Bool = true) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(info(doc)), as: UTF8.self)
    }

    /// 注釈の JSON 配列を読む。`number` のないスタンプには `doc` にある同じ種類の続きから番号を振る。
    public static func decodeAnnotations(_ data: Data, continuingFrom doc: Document) throws -> [Annotation] {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) } catch {
            throw ToolError.invalidAnnotations("not valid JSON (\(error.localizedDescription))")
        }
        guard let items = raw as? [Any] else { throw ToolError.invalidAnnotations("expected a JSON array of annotations") }

        var counters: [String: Int] = [:]
        for a in doc.annotations {
            guard case .stamp(let s) = a.content, s.kind.isSequential else { continue }
            counters[stampKey(s.kind), default: 0] = max(counters[stampKey(s.kind)] ?? 0, s.number)
        }

        var result: [Annotation] = []
        for (i, item) in items.enumerated() {
            guard var obj = item as? [String: Any] else { throw ToolError.invalidAnnotations("[\(i)] is not an object") }
            let type = obj["type"] as? String ?? ""
            guard annotationTypes.contains(type) else {
                throw ToolError.invalidAnnotations("[\(i)] unknown type \"\(type)\" (expected one of \(annotationTypes.joined(separator: ", ")))")
            }
            if type == "stamp", obj["number"] == nil {
                let kind = (obj["style"] as? [String: Any])?["kind"] as? String ?? "number"
                if kind == "number" || kind == "letter" {
                    let n = (counters[kind] ?? 0) + 1
                    counters[kind] = n
                    obj["number"] = n
                }
            } else if type == "stamp", let n = obj["number"] as? Int {
                let kind = (obj["style"] as? [String: Any])?["kind"] as? String ?? "number"
                counters[kind] = max(counters[kind] ?? 0, n)
            }
            do {
                let a = try JSONDecoder().decode(Annotation.self, from: JSONSerialization.data(withJSONObject: obj))
                if case .unknown = a.content { throw ToolError.invalidAnnotations("[\(i)] could not be read as \(type)") }
                result.append(a)
            } catch let e as DecodingError {
                throw ToolError.invalidAnnotations("[\(i)] \(type): \(describe(e))")
            }
        }
        return result
    }

    /// 注釈・切り抜き・倍率を加えた文書。
    public static func applying(annotations: [Annotation], crop: CGRect?, scale: Double?, to doc: Document) -> Document {
        var ops = annotations.map { EditOperation.add($0) }
        if let crop { ops.append(.setCrop(crop)) }
        if let scale { ops.append(.setOutputScale(scale)) }
        return doc.applying(ops)
    }

    /// 出力の種類に合わせてエンコードする。`.kakiire` では元の manifest の作成日時を引き継ぐ。
    public static func encode(_ doc: Document, as kind: OutputKind, manifest: Manifest? = nil) throws -> Data {
        switch kind {
        case .image(let format):
            return try ImageExport.data(of: doc, format: format)
        case .archive:
            var m = manifest ?? Manifest(appVersion: appVersion)
            m.appVersion = appVersion
            m.updatedAt = Date()
            return try KakiireArchive.write(doc, manifest: m)
        }
    }

    /// 読み込み → 注釈の追加 → 書き出しを1回で行い、書き出した文書を返す。
    @discardableResult
    public static func annotate(_ req: AnnotateRequest) throws -> Document {
        try annotateReturningAdded(req).document
    }

    /// `annotate` と同じ。足した注釈も返す。書き出し先はすべて確かめてから書く(途中で失敗して一部だけ残らないように)。
    public static func annotateReturningAdded(_ req: AnnotateRequest) throws -> AnnotateResult {
        guard !req.outputs.isEmpty else { throw ToolError.usage("output is required") }
        let input = req.input.standardizedFileURL.resolvingSymlinksInPath()
        let kinds = try req.outputs.map { out in
            let kind = try OutputKind(url: out)
            if !req.force, input == out.standardizedFileURL.resolvingSymlinksInPath() {
                throw ToolError.wouldOverwriteInput(req.input.path)
            }
            return kind
        }
        let loaded = try load(req.input)
        if loaded.isReadOnly, kinds.contains(.archive) { throw ToolError.readOnly(req.input.path) }
        let added = try req.annotations.map { try decodeAnnotations($0, continuingFrom: loaded.document) } ?? []
        let doc = applying(annotations: added, crop: req.crop, scale: req.scale, to: loaded.document)
        let encoded = try kinds.map { try encode(doc, as: $0, manifest: loaded.manifest) }
        for (data, out) in zip(encoded, req.outputs) { try data.write(to: out, options: .atomic) }
        return AnnotateResult(document: doc, added: added)
    }

    static func stampKey(_ k: StampKind) -> String { k == .letter ? "letter" : "number" }

    /// `DecodingError` を「どのキーが・なぜ」の1行にする。
    static func describe(_ e: DecodingError) -> String {
        func path(_ p: [any CodingKey]) -> String {
            p.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let k, let c):
            let at = path(c.codingPath)
            return "missing \"\(k.stringValue)\"" + (at.isEmpty ? "" : " in \(at)")
        case .typeMismatch(let t, let c): return "\(path(c.codingPath)): expected \(t)"
        case .valueNotFound(let t, let c): return "\(path(c.codingPath)): expected \(t)"
        case .dataCorrupted(let c): return "\(path(c.codingPath)): \(c.debugDescription)"
        @unknown default: return e.localizedDescription
        }
    }
}

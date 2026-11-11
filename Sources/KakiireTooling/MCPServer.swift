import CoreGraphics
import Foundation
import KakiireCore
import KakiireIO

/// 標準入出力の MCP サーバー(JSON-RPC 2.0、1行に1メッセージ)。
///
/// 入出力は持たず、1行を受けて応答の1行(通知なら nil)を返すだけにしてある。テストから直接呼ぶため。
public struct MCPServer {
    /// 知っている版。クライアントが求めた版がこの中にあればそれを返し、なければ先頭を返す。
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public init() {}

    public func handle(line: String) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = obj["id"], !(id is NSNull) else { return nil }  // 通知には応答しない
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any] ?? [:]

        let result: [String: Any]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            result = [
                "protocolVersion": Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "kakiire", "version": KakiireTool.appVersion],
                "instructions": Self.instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools]
        case "tools/call":
            result = call(name: params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])
        default:
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
        return Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    // MARK: - ツール

    func call(name: String, arguments a: [String: Any]) -> [String: Any] {
        do {
            switch name {
            case "get_image_info":
                let url = try Self.fileURL(a["path"], key: "path")
                let doc = try KakiireTool.load(url).document
                let region = try Self.rect(a["preview_region"], key: "preview_region")
                var content: [[String: Any]] = [Self.text(try KakiireTool.infoJSON(doc, pretty: false))]
                if a["preview"] as? Bool ?? true || region != nil { content += try Self.preview(doc, region: region) }
                return ["content": content, "isError": false]
            case "annotate_image":
                let input = try Self.fileURL(a["input"], key: "input")
                let outputs: [URL] = try {
                    switch a["output"] {
                    case let list as [Any]:
                        guard !list.isEmpty else { throw ToolError.usage("output is required") }
                        return try list.map { try Self.fileURL($0, key: "output") }
                    case let v: return [try Self.fileURL(v, key: "output")]
                    }
                }()
                let annotations: Data? = try {
                    switch a["annotations"] {
                    case nil, is NSNull: return nil
                    case let s as String: return Data(s.utf8)
                    case let v?: return try JSONSerialization.data(withJSONObject: v)
                    }
                }()
                let crop = try Self.rect(a["crop"], key: "crop")
                let region = try Self.rect(a["preview_region"], key: "preview_region")
                let result = try KakiireTool.annotateReturningAdded(AnnotateRequest(
                    input: input, outputs: outputs, annotations: annotations,
                    crop: crop, scale: a["scale"] as? Double, force: a["force"] as? Bool ?? false))
                let doc = result.document
                let info = KakiireTool.info(doc)
                let paths = outputs.map(\.path).joined(separator: ", ")
                var content = [Self.text("Wrote \(paths) (\(info.outputWidth)x\(info.outputHeight) px, \(doc.annotations.count) annotations).")]
                if !result.added.isEmpty {
                    let e = JSONEncoder()
                    e.outputFormatting = [.sortedKeys]
                    let json = String(decoding: try e.encode(KakiireTool.drawnBounds(result.added)), as: UTF8.self)
                    content.append(Self.text("Drawn bounds of the annotations you passed ([x, y, w, h] in image pixels, including stroke, arrowhead and outline; for text, glyphs excludes the outline padding): \(json)"))
                }
                return ["content": content + (try Self.preview(doc, region: region)), "isError": false]
            default:
                return ["content": [Self.text("Unknown tool: \(name)")], "isError": true]
            }
        } catch {
            return ["content": [Self.text(error.localizedDescription)], "isError": true]
        }
    }

    /// 範囲を拡大するときの倍率の上限。数 px のずれが見える程度にとどめる。
    static let maxRegionZoom: CGFloat = 4

    /// 焼き込み済みのプレビューと、その倍率の説明。
    ///
    /// `region` がなければ出力全体を長辺 1024px に縮める。あれば、その範囲(元画像のピクセル)を長辺 1024px まで拡大する(4倍まで)。
    static func preview(_ doc: Document, region: CGRect? = nil) throws -> [[String: Any]] {
        var d = doc
        let area: CGRect
        let f: CGFloat
        if let region {
            // effectiveCrop は空の切り抜きを画像全体に戻すので、重ならない範囲はここで断る。
            let r = region.standardized.integral.intersection(doc.effectiveCrop)
            guard !r.isNull, r.width >= 1, r.height >= 1 else {
                throw ToolError.usage("preview_region does not overlap the output area \(rectText(doc.effectiveCrop))")
            }
            area = r
            f = min(maxRegionZoom, KakiireArchive.previewMaxSide / max(r.width, r.height))
            d.canvas.crop = r
        } else {
            area = doc.effectiveCrop
            f = min(1, KakiireArchive.previewMaxSide / max(area.width, area.height, 1))
        }
        d.canvas.outputScale = f
        guard let img = Renderer.makeImage(d) else { throw ImageExportError.renderFailed }
        let png = try ImageExport.data(img, format: .png)
        var note = region == nil
            ? "Preview below shows the output with annotations burned in."
            : "Preview below shows region \(rectText(area)) with annotations burned in."
        if f != 1 || area.origin != .zero {
            note += String(format: " It is scaled by %.4f; image_x = %.0f + preview_x / %.4f, image_y = %.0f + preview_y / %.4f.",
                           f, area.minX, f, area.minY, f)
        }
        return [text(note), ["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]]
    }

    static func rectText(_ r: CGRect) -> String {
        "[\(Int(r.minX)), \(Int(r.minY)), \(Int(r.width)), \(Int(r.height))]"
    }

    /// `[x, y, w, h]`。なければ nil。
    static func rect(_ v: Any?, key: String) throws -> CGRect? {
        switch v {
        case nil, is NSNull: return nil
        case let c as [Double] where c.count == 4 && c[2] > 0 && c[3] > 0:
            return CGRect(x: c[0], y: c[1], width: c[2], height: c[3])
        default: throw ToolError.usage("\(key) must be [x, y, w, h] with positive w and h")
        }
    }

    static func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }

    static func fileURL(_ v: Any?, key: String) throws -> URL {
        guard let s = v as? String, !s.isEmpty else { throw ToolError.usage("\(key) is required") }
        let path = (s as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { throw ToolError.usage("\(key) must be an absolute path: \(s)") }
        return URL(fileURLWithPath: path)
    }

    static func encode(_ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static let instructions = """
    Kakiire annotates screenshots and images (arrows, boxes, text, numbered stamps, mosaic/blur) \
    and writes PNG/JPEG or an editable .kakiire file. Call get_image_info first to learn the pixel size \
    and see the image, then annotate_image. Coordinates are image pixels (top-left origin, y down), \
    not points: Retina screenshots are usually 2x their point size. get_image_info returns "suggested" \
    stroke widths and font sizes for this image. annotate_image returns the drawn bounds of each annotation \
    you passed (use a text's glyphs box to place underlines or arrows). To check small offsets, pass \
    preview_region to see a zoomed-in part of the result. Pass several output paths to write .png and \
    .kakiire at once.
    """

    static let annotationsHelp = """
    JSON array. Each item: {"type", "geometry", "style", ...}. Points are [x, y], rects are [x, y, w, h], \
    colors are "#RRGGBB" or "#RRGGBBAA". Optional on every item: "name", "hidden", "locked".
    - arrow: geometry {from, to}; style {color, width, arrow?: "tapered"|"open", dash?, outline?: bool}
    - line: geometry {from, to}; style {color, width, dash?}
    - rect / ellipse: geometry {rect}; style {color, width, fill?, dash?}
    - text: geometry {origin (top-left)}; "text": "..."; style {color, fontSize, bold?, outline?}
    - obscure: geometry {rect}; style {mode: "pixelate"|"blur", strength (px)}
    - highlighter / pen: geometry {points: [[x,y], ...]}; style {color, width, dash?}
    - stamp: geometry {center}; style {color, diameter, kind?: "letter"|"symbol"|"emoji"}; \
    "number" optional (auto-continues), "symbol" for symbol/emoji
    dash: "solid"|"dashed"|"dotted"|"dashDot". Palette: red #E82A2A, pink #E5306B, orange #F58A1F, \
    yellow #FFD60A, green #2EB84E, blue #1E7CF0, purple #8E44D9, black #1D1D1F, white #FFFFFF. \
    For widths and sizes, use "suggested" from get_image_info (it scales with the image width).
    """

    static var regionSchema: [String: Any] { [
        "type": "array", "items": ["type": "number"],
        "description": "Optional [x, y, w, h] in image pixels. Return a zoomed-in preview of this part instead of the whole image (up to 4x), to check small offsets.",
    ] }

    static var tools: [[String: Any]] {
        [
            [
                "name": "get_image_info",
                "description": "Read an image file (PNG/JPEG/HEIC...) or a .kakiire document. Returns pixel size, crop, output size and existing annotations as JSON, plus a preview image.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute path to the image or .kakiire file"],
                        "preview": ["type": "boolean", "description": "Include a preview image (default true)"],
                        "preview_region": regionSchema,
                    ],
                    "required": ["path"],
                ],
            ],
            [
                "name": "annotate_image",
                "description": "Add annotations to an image or .kakiire and write the result. The output format follows the extension: .png, .jpg/.jpeg (flattened, annotations burned in) or .kakiire (editable in the Kakiire app). Returns a preview of the result.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "input": ["type": "string", "description": "Absolute path to the source image or .kakiire"],
                        "output": [
                            "type": ["string", "array"], "items": ["type": "string"],
                            "description": "Absolute output path ending in .png, .jpg, .jpeg or .kakiire, or an array of them to write several formats at once",
                        ],
                        "annotations": ["type": "array", "items": ["type": "object"], "description": annotationsHelp],
                        "crop": ["type": "array", "items": ["type": "number"], "description": "Optional crop [x, y, w, h] in image pixels"],
                        "scale": ["type": "number", "description": "Optional output scale (e.g. 0.5 to halve a Retina screenshot)"],
                        "force": ["type": "boolean", "description": "Allow output to be the same file as input (default false)"],
                        "preview_region": regionSchema,
                    ],
                    "required": ["input", "output"],
                ],
            ],
        ]
    }
}

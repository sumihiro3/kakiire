import CoreGraphics
import Foundation

// document.json の注釈の形:
//   { "id", "type", "name", "hidden", "locked", "geometry": {...}, "style": {...}, "text"(text のみ) }
// 点は [x, y]、矩形は [x, y, w, h]。

extension Annotation: Codable {
    enum Keys: String, CodingKey { case id, type, name, hidden, locked, geometry, style, text, asset, number }
    enum GeometryKeys: String, CodingKey { case from, to, rect, origin, points, center }
    enum StyleKeys: String, CodingKey { case color, width, arrow, fill, fontSize, bold, outline, mode, strength, diameter, rotation, flipH, flipV, dash }

    /// 画像オーバーレイの読み込みに使う `[ファイル名: ImageAsset]` を `decoder.userInfo` に入れるキー。
    public static let assetsUserInfoKey = CodingUserInfoKey(rawValue: "kakiire.assets")!

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        let idString = try c.decodeIfPresent(String.self, forKey: .id)
        id = idString.flatMap(UUID.init(uuidString:)) ?? UUID()
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false

        switch type {
        case "arrow":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            content = .arrow(ArrowSpec(
                from: try g.decodePoint(.from), to: try g.decodePoint(.to),
                color: try s.decode(RGBAColor.self, forKey: .color),
                width: try s.decode(Double.self, forKey: .width),
                head: (try? s.decodeIfPresent(ArrowHead.self, forKey: .arrow)) ?? .tapered,
                dash: s.decodeDash(),
                outline: (try? s.decodeIfPresent(Bool.self, forKey: .outline)) ?? false))
        case "line":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            content = .line(LineSpec(
                from: try g.decodePoint(.from), to: try g.decodePoint(.to),
                color: try s.decode(RGBAColor.self, forKey: .color),
                width: try s.decode(Double.self, forKey: .width),
                dash: s.decodeDash()))
        case "rect", "ellipse":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            let spec = ShapeSpec(
                rect: try g.decodeRect(.rect),
                color: try s.decode(RGBAColor.self, forKey: .color),
                width: try s.decode(Double.self, forKey: .width),
                fill: try s.decodeIfPresent(RGBAColor.self, forKey: .fill),
                dash: s.decodeDash())
            content = type == "rect" ? .rect(spec) : .ellipse(spec)
        case "text":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            content = .text(TextSpec(
                origin: try g.decodePoint(.origin),
                text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                color: try s.decode(RGBAColor.self, forKey: .color),
                fontSize: try s.decode(Double.self, forKey: .fontSize),
                bold: try s.decodeIfPresent(Bool.self, forKey: .bold) ?? true,
                outline: try s.decodeIfPresent(Bool.self, forKey: .outline) ?? true))
        case "obscure":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            content = .obscure(ObscureSpec(
                rect: try g.decodeRect(.rect),
                mode: try s.decodeIfPresent(ObscureMode.self, forKey: .mode) ?? .pixelate,
                strength: try s.decodeIfPresent(Double.self, forKey: .strength) ?? 12))
        case "highlighter", "pen":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            let spec = StrokeSpec(
                points: try g.decode([[Double]].self, forKey: .points).compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil },
                color: try s.decode(RGBAColor.self, forKey: .color),
                width: try s.decode(Double.self, forKey: .width),
                dash: s.decodeDash())
            content = type == "pen" ? .pen(spec) : .highlighter(spec)
        case "stamp":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            content = .stamp(StampSpec(
                center: try g.decodePoint(.center),
                number: try c.decodeIfPresent(Int.self, forKey: .number) ?? 1,
                color: try s.decode(RGBAColor.self, forKey: .color),
                diameter: try s.decode(Double.self, forKey: .diameter)))
        case "image":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let path = try c.decode(String.self, forKey: .asset)
            let assets = decoder.userInfo[Self.assetsUserInfoKey] as? [String: ImageAsset] ?? [:]
            if let asset = assets[path] {
                let s = try? c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
                content = .image(ImageSpec(
                    asset: asset, rect: try g.decodeRect(.rect),
                    rotation: (try? s?.decodeIfPresent(Rotation.self, forKey: .rotation)) ?? .r0,
                    flipH: (try? s?.decodeIfPresent(Bool.self, forKey: .flipH)) ?? false,
                    flipV: (try? s?.decodeIfPresent(Bool.self, forKey: .flipV)) ?? false))
            } else {
                // 素材が欠けていても文書は開けるようにし、JSON は残す。
                content = .unknown(type: type, raw: try JSONValue(from: decoder))
            }
        default:
            content = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? content.typeName
    }

    public func encode(to encoder: any Encoder) throws {
        if case .unknown(_, let raw) = content {
            // 中身は触らず、レイヤー操作で変わりうる共通フィールドだけ上書きする。
            var merged: [String: JSONValue] = if case .object(let o) = raw { o } else { [:] }
            merged["id"] = .string(id.uuidString)
            merged["name"] = .string(name)
            merged["hidden"] = .bool(hidden)
            merged["locked"] = .bool(locked)
            try JSONValue.object(merged).encode(to: encoder)
            return
        }

        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id.uuidString, forKey: .id)
        try c.encode(content.typeName, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(locked, forKey: .locked)
        var g = c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
        var s = c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)

        switch content {
        case .arrow(let a):
            try g.encodePoint(a.from, .from); try g.encodePoint(a.to, .to)
            try s.encode(a.color, forKey: .color); try s.encode(a.width, forKey: .width)
            try s.encode(a.head, forKey: .arrow)
            try s.encodeDash(a.dash)
            // 縁なしは書かない(古い版の文書と同じ形のまま)。
            if a.outline { try s.encode(true, forKey: .outline) }
        case .line(let l):
            try g.encodePoint(l.from, .from); try g.encodePoint(l.to, .to)
            try s.encode(l.color, forKey: .color); try s.encode(l.width, forKey: .width)
            try s.encodeDash(l.dash)
        case .rect(let r), .ellipse(let r):
            try g.encodeRect(r.rect, .rect)
            try s.encode(r.color, forKey: .color); try s.encode(r.width, forKey: .width)
            try s.encodeIfPresent(r.fill, forKey: .fill)
            try s.encodeDash(r.dash)
        case .text(let t):
            try g.encodePoint(t.origin, .origin)
            try c.encode(t.text, forKey: .text)
            try s.encode(t.color, forKey: .color); try s.encode(t.fontSize, forKey: .fontSize)
            try s.encode(t.bold, forKey: .bold); try s.encode(t.outline, forKey: .outline)
        case .obscure(let o):
            try g.encodeRect(o.rect, .rect)
            try s.encode(o.mode, forKey: .mode); try s.encode(o.strength, forKey: .strength)
        case .highlighter(let p), .pen(let p):
            try g.encode(p.points.map { [Double($0.x), Double($0.y)] }, forKey: .points)
            try s.encode(p.color, forKey: .color); try s.encode(p.width, forKey: .width)
            try s.encodeDash(p.dash)
        case .stamp(let st):
            try g.encodePoint(st.center, .center)
            try c.encode(st.number, forKey: .number)
            try s.encode(st.color, forKey: .color); try s.encode(st.diameter, forKey: .diameter)
        case .image(let im):
            try g.encodeRect(im.rect, .rect)
            try c.encode(im.assetPath, forKey: .asset)
            try s.encode(im.rotation, forKey: .rotation)
            try s.encode(im.flipH, forKey: .flipH); try s.encode(im.flipV, forKey: .flipV)
        case .unknown:
            break
        }
    }
}

extension KeyedDecodingContainer {
    func decodePoint(_ key: Key) throws -> CGPoint {
        let v = try decode([Double].self, forKey: key)
        guard v.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "point needs 2 numbers")
        }
        return CGPoint(x: v[0], y: v[1])
    }

    func decodeRect(_ key: Key) throws -> CGRect {
        let v = try decode([Double].self, forKey: key)
        guard v.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "rect needs 4 numbers")
        }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }
}

extension KeyedDecodingContainer where Key == Annotation.StyleKeys {
    /// 線の種類。ないとき・知らない値のときは実線。
    func decodeDash() -> LineDash {
        (try? decodeIfPresent(LineDash.self, forKey: .dash)) ?? .solid
    }
}

extension KeyedEncodingContainer where Key == Annotation.StyleKeys {
    /// 実線は書かない(古い版の文書と同じ形のまま)。
    mutating func encodeDash(_ d: LineDash) throws {
        if d != .solid { try encode(d, forKey: .dash) }
    }
}

extension KeyedEncodingContainer {
    mutating func encodePoint(_ p: CGPoint, _ key: Key) throws {
        try encode([Double(p.x), Double(p.y)], forKey: key)
    }

    mutating func encodeRect(_ r: CGRect, _ key: Key) throws {
        try encode([Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)], forKey: key)
    }
}

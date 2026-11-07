import CoreGraphics
import Foundation

// document.json の注釈の形:
//   { "id", "type", "name", "hidden", "locked", "geometry": {...}, "style": {...}, "text"(text のみ) }
// 点は [x, y]、矩形は [x, y, w, h]。

extension Annotation: Codable {
    enum Keys: String, CodingKey { case id, type, name, hidden, locked, geometry, style, text }
    enum GeometryKeys: String, CodingKey { case from, to, rect, origin }
    enum StyleKeys: String, CodingKey { case color, width, arrow, fill, fontSize, bold, outline, mode, strength }

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
                head: (try? s.decodeIfPresent(ArrowHead.self, forKey: .arrow)) ?? .tapered))
        case "line":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            content = .line(LineSpec(
                from: try g.decodePoint(.from), to: try g.decodePoint(.to),
                color: try s.decode(RGBAColor.self, forKey: .color),
                width: try s.decode(Double.self, forKey: .width)))
        case "rect", "ellipse":
            let g = try c.nestedContainer(keyedBy: GeometryKeys.self, forKey: .geometry)
            let s = try c.nestedContainer(keyedBy: StyleKeys.self, forKey: .style)
            let spec = ShapeSpec(
                rect: try g.decodeRect(.rect),
                color: try s.decode(RGBAColor.self, forKey: .color),
                width: try s.decode(Double.self, forKey: .width),
                fill: try s.decodeIfPresent(RGBAColor.self, forKey: .fill))
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
        default:
            content = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? content.displayName
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
        case .line(let l):
            try g.encodePoint(l.from, .from); try g.encodePoint(l.to, .to)
            try s.encode(l.color, forKey: .color); try s.encode(l.width, forKey: .width)
        case .rect(let r), .ellipse(let r):
            try g.encodeRect(r.rect, .rect)
            try s.encode(r.color, forKey: .color); try s.encode(r.width, forKey: .width)
            try s.encodeIfPresent(r.fill, forKey: .fill)
        case .text(let t):
            try g.encodePoint(t.origin, .origin)
            try c.encode(t.text, forKey: .text)
            try s.encode(t.color, forKey: .color); try s.encode(t.fontSize, forKey: .fontSize)
            try s.encode(t.bold, forKey: .bold); try s.encode(t.outline, forKey: .outline)
        case .obscure(let o):
            try g.encodeRect(o.rect, .rect)
            try s.encode(o.mode, forKey: .mode); try s.encode(o.strength, forKey: .strength)
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

extension KeyedEncodingContainer {
    mutating func encodePoint(_ p: CGPoint, _ key: Key) throws {
        try encode([Double(p.x), Double(p.y)], forKey: key)
    }

    mutating func encodeRect(_ r: CGRect, _ key: Key) throws {
        try encode([Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)], forKey: key)
    }
}

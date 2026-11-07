import CoreGraphics

/// 8bit sRGB の色。JSON では CSS と同じ `#RRGGBB` / `#RRGGBBAA` の文字列で持つ。
public struct RGBAColor: Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `#RRGGBB` または `#RRGGBBAA` を読む。形式が違えば nil。
    public init?(hex: String) {
        var s = Substring(hex.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
        } else {
            self.init(UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
        }
    }

    /// `#RRGGBB`(不透明)または `#RRGGBBAA`。
    public var hex: String {
        let rgb = String(format: "#%02X%02X%02X", r, g, b)
        return a == 255 ? rgb : rgb + String(format: "%02X", a)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    public static let pink = RGBAColor(0xE5, 0x30, 0x6B)
    public static let red = RGBAColor(0xE8, 0x2A, 0x2A)
    public static let orange = RGBAColor(0xF5, 0x8A, 0x1F)
    public static let yellow = RGBAColor(0xFF, 0xD6, 0x0A)
    public static let green = RGBAColor(0x2E, 0xB8, 0x4E)
    public static let blue = RGBAColor(0x1E, 0x7C, 0xF0)
    public static let purple = RGBAColor(0x8E, 0x44, 0xD9)
    public static let black = RGBAColor(0x1D, 0x1D, 0x1F)
    public static let white = RGBAColor(0xFF, 0xFF, 0xFF)

    /// ツールバーの色パレット。
    public static let palette: [RGBAColor] = [.pink, .red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

extension RGBAColor: Codable {
    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = RGBAColor(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid color \(s)"))
        }
        self = c
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

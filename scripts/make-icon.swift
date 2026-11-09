// アプリアイコンを作る。図形は 104 マスの座標で一度だけ書き、
// SVG の原図(docs/icon/kakiire-icon.svg)と AppIcon.appiconset の PNG を両方ここから出す。
// 使い方: swift scripts/make-icon.swift(リポジトリの直下で)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Shape {
    let d: String
    let fill: String?
    let stroke: (color: String, width: CGFloat)?
}

let grid: CGFloat = 104
let cornerRadius: CGFloat = 24
let tileColor = "#F1EFE8"

// 矢印はアプリの ArrowPath.tapered と同じ作り(尾が太く、細い首、後ろに返した矢じり)。
// アイコンの大きさでも潰れないよう、首と矢じりだけ太らせてある。
let arrow = "M75.1 8.6 Q58.6 30.3 45.9 45.4 L34.3 30.4 L27.0 74.0 L69.6 62.2 L53.5 52.2 Q67.1 38.0 86.9 19.4 Z"

let shapes: [Shape] = [
    Shape(d: "M18 54 H86 Q92 54 92 60 V90 Q92 96 86 96 H18 Q12 96 12 90 V60 Q12 54 18 54 Z", fill: "#B5D4F4", stroke: nil),
    Shape(d: "M12 90 L27 76 L42 86 L60 78 L92 90 Q92 96 86 96 H18 Q12 96 12 90 Z", fill: "#97C459", stroke: nil),
    Shape(d: "M27 76 L21.5 81.5 L25 80.5 L27 82.5 L29.5 80.5 L32.5 81.5 Z", fill: "#FFFFFF", stroke: nil),
    Shape(d: arrow, fill: nil, stroke: ("#791F1F", 7)),
    Shape(d: arrow, fill: "#E82A2A", stroke: ("#FFFFFF", 3.5)),
]

// macOS のアイコン枠: 1024 のうち 824 が本体、周りは影の余白。
let canvas: CGFloat = 1024
let body: CGFloat = 824
let inset = (canvas - body) / 2

func color(_ hex: String) -> CGColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// M / L / Q / H / V / Z(絶対座標)だけを読む。
func path(_ d: String) -> CGPath {
    let tokens = d.replacingOccurrences(of: ",", with: " ")
        .replacingOccurrences(of: #"([A-Za-z])"#, with: " $1 ", options: .regularExpression)
        .split(separator: " ").map(String.init)
    let p = CGMutablePath()
    var i = 0, cmd = "", cur = CGPoint.zero
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        if tokens[i].first!.isLetter { cmd = tokens[i]; i += 1 }
        switch cmd {
        case "M": cur = CGPoint(x: num(), y: num()); p.move(to: cur); cmd = "L"
        case "L": cur = CGPoint(x: num(), y: num()); p.addLine(to: cur)
        case "H": cur.x = num(); p.addLine(to: cur)
        case "V": cur.y = num(); p.addLine(to: cur)
        case "Q":
            let c = CGPoint(x: num(), y: num())
            cur = CGPoint(x: num(), y: num()); p.addQuadCurve(to: cur, control: c)
        case "Z": p.closeSubpath()
        default: fatalError("unsupported command \(cmd)")
        }
    }
    return p
}

func render(size: Int) -> CGImage {
    let px = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = px / canvas
    // SVG と同じ左上原点・y 下向きにそろえる。
    ctx.translateBy(x: 0, y: px)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: inset * k, y: inset * k)
    ctx.scaleBy(x: body * k / grid, y: body * k / grid)

    let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: grid, height: grid),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(tile); ctx.setFillColor(color(tileColor)); ctx.fillPath()
    ctx.restoreGState()

    ctx.setLineJoin(.round)
    for s in shapes {
        let p = path(s.d)
        if let f = s.fill { ctx.addPath(p); ctx.setFillColor(color(f)); ctx.fillPath() }
        if let st = s.stroke {
            ctx.addPath(p); ctx.setStrokeColor(color(st.color)); ctx.setLineWidth(st.width); ctx.strokePath()
        }
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let assets = root.appendingPathComponent("App/Resources/Assets.xcassets")
let iconset = assets.appendingPathComponent("AppIcon.appiconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.appending("\n")
    .write(to: assets.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        writePNG(render(size: px), to: iconset.appendingPathComponent(name))
        images.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(pt)x\#(pt)" }"#)
    }
}
try ("{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n")
    .write(to: iconset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let docs = root.appendingPathComponent("docs/icon")
try fm.createDirectory(at: docs, withIntermediateDirectories: true)
var svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <g transform="translate(\(Int(inset)) \(Int(inset))) scale(\(body / grid))">
    <rect width="\(Int(grid))" height="\(Int(grid))" rx="\(Int(cornerRadius))" fill="\(tileColor)"/>

"""
for s in shapes {
    let stroke = s.stroke.map { #" stroke="\#($0.color)" stroke-width="\#($0.width)" stroke-linejoin="round""# } ?? ""
    svg += #"    <path d="\#(s.d)" fill="\#(s.fill ?? "none")"\#(stroke)/>"# + "\n"
}
svg += "  </g>\n</svg>\n"
try svg.write(to: docs.appendingPathComponent("kakiire-icon.svg"), atomically: true, encoding: .utf8)
writePNG(render(size: 1024), to: docs.appendingPathComponent("kakiire-icon-1024.png"))
print("wrote \(images.count) PNGs to \(iconset.path) and docs/icon/")

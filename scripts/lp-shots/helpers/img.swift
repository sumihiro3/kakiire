import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 使い方: img bbox <in> / img crop <in> <out> x y w h
let a = CommandLine.arguments
func load(_ p: String) -> CGImage {
    let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(s, 0, nil)!
}
func save(_ img: CGImage, _ p: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: p) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
}
let img = load(a[2])
if a[1] == "bbox" {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var x0 = w, y0 = h, x1 = 0, y1 = 0
    for y in 0..<h { for x in 0..<w where buf[(y * w + x) * 4 + 3] == 255 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    print(w, h, "opaque:", x0, y0, x1 - x0 + 1, y1 - y0 + 1)
} else {
    let r = CGRect(x: Double(a[4])!, y: Double(a[5])!, width: Double(a[6])!, height: Double(a[7])!)
    save(img.cropping(to: r)!, a[3])
}

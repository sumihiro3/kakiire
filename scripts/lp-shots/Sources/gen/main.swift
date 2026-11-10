import CoreGraphics
import Foundation
import KakiireCore
import KakiireIO

// LP 用のサンプル文書を作る。使い方: gen <base.png> <出力フォルダ>
let args = CommandLine.arguments
let baseURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let base = try ImageImport.asset(contentsOf: baseURL)
let manifest = Manifest(appVersion: "0.5.0")

func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
func rc(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

func write(_ doc: Document, _ name: String) throws {
    let data = try KakiireArchive.write(doc, manifest: manifest)
    try data.write(to: outDir.appendingPathComponent(name))
    if let img = Renderer.makeImage(doc, cache: RenderCache()) {
        let png = try ImageExport.data(img, format: .png)
        try png.write(to: outDir.appendingPathComponent(name.replacingOccurrences(of: ".kakiire", with: "-export.png")))
    }
}

// 1. 道具の見本。道具ごとに 320×201 で切り出すので、切り出す範囲に他の注釈が入らない位置に置く
let check = [pt(1150, 640), pt(1156, 647), pt(1163, 655), pt(1171, 645), pt(1180, 634), pt(1191, 622)]
let tools = Document(base: BaseImage(asset: base), annotations: [
    Annotation(name: "モザイク 1", content: .obscure(ObscureSpec(rect: rc(328, 328, 222, 30), mode: .pixelate, strength: 12))),
    Annotation(name: "ぼかし 1", content: .obscure(ObscureSpec(rect: rc(1132, 10, 132, 36), mode: .blur, strength: 12 * 1.4))),
    Annotation(name: "ハイライター 1", content: .highlighter(StrokeSpec(points: [pt(324, 539), pt(596, 539)], color: .yellow, width: 28))),
    Annotation(name: "線 1", content: .line(LineSpec(from: pt(289, 123), to: pt(468, 123), color: .blue, width: 4))),
    Annotation(name: "楕円 1", content: .ellipse(ShapeSpec(rect: rc(968, 476, 160, 60), color: .pink, width: 4))),
    Annotation(name: "矩形 1", content: .rect(ShapeSpec(rect: rc(974, 326, 244, 60), color: .red, width: 8))),
    Annotation(name: "ペン 1", content: .pen(StrokeSpec(points: check, color: .green, width: 8))),
    Annotation(name: "スタンプ 1", content: .stamp(StampSpec(center: pt(748, 248), number: 1, color: .red, diameter: 40))),
    Annotation(name: "スタンプ 2", content: .stamp(StampSpec(center: pt(748, 342), number: 2, color: .red, diameter: 40))),
    Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: pt(268, 292), to: pt(112, 236), color: .red, width: 20, outline: true))),
    Annotation(name: "テキスト 1", content: .text(TextSpec(origin: pt(322, 646), text: "保存を忘れずに", color: .red, fontSize: 30))),
])
try write(tools, "道具の見本.kakiire")

// 切り抜きの見本用。注釈なし
try write(Document(base: BaseImage(asset: base)), "切り抜きの例.kakiire")

// 2. ボタンの拡大図を重ねた文書
let cropRect = rc(308, 562, 172, 66)
let scale = 2.0
guard let cropped = base.cgImage.cropping(to: cropRect) else { fatalError("crop") }
let w = Int(cropRect.width * scale), h = Int(cropRect.height * scale)
guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("ctx") }
ctx.interpolationQuality = .high
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
let zoom = try ImageImport.asset(from: ctx.makeImage()!)

// 左のカードだけを切り出した小さい元画像(ウインドウを小さくして、中身を大きく見せる)
let card = try ImageImport.asset(from: base.cgImage.cropping(to: rc(272, 156, 672, 592))!)

let overlay = Document(base: BaseImage(asset: card), annotations: [
    Annotation(name: "画像 1", content: .image(ImageSpec(
        asset: zoom, rect: rc(300, 424, Double(w), Double(h)),
        border: ImageBorder(color: .red, width: 4, position: .outside), shadow: 12))),
    Annotation(name: "矩形 1", content: .rect(ShapeSpec(rect: rc(36, 404, 172, 70), color: .red, width: 4))),
    Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: pt(214, 460), to: pt(290, 488), color: .red, width: 12, outline: true))),
])
try write(overlay, "ボタンの拡大.kakiire")

// 3. レイヤーの説明用(名前を付けた層、ロックした層、隠した層)
let layers = Document(base: BaseImage(asset: card), annotations: [
    Annotation(name: "メールを隠す", locked: true, content: .obscure(ObscureSpec(rect: rc(58, 174, 216, 26), mode: .pixelate, strength: 12))),
    Annotation(name: "ハイライター 1", content: .highlighter(StrokeSpec(points: [pt(52, 383), pt(324, 383)], color: .yellow, width: 28))),
    Annotation(name: "保存ボタンの枠", content: .rect(ShapeSpec(rect: rc(36, 404, 172, 70), color: .red, width: 8))),
    Annotation(name: "スタンプ 1", content: .stamp(StampSpec(center: pt(476, 92), number: 1, color: .red, diameter: 40))),
    Annotation(name: "スタンプ 2", content: .stamp(StampSpec(center: pt(476, 186), number: 2, color: .red, diameter: 40))),
    Annotation(name: "スタンプ 3", content: .stamp(StampSpec(center: pt(334, 550), number: 3, color: .red, diameter: 40))),
    Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: pt(332, 516), to: pt(204, 478), color: .red, width: 20, outline: true))),
    Annotation(name: "テキスト 1", content: .text(TextSpec(origin: pt(364, 532), text: "最後にここを押す", color: .red, fontSize: 30))),
    Annotation(name: "下書きのメモ", hidden: true, content: .text(TextSpec(origin: pt(300, 262), text: "あとで消す", color: .blue, fontSize: 30))),
])
try write(layers, "手順の説明.kakiire")

// 4. ファーストビューの層の図に貼る画像。3つ目の引数に 2 倍で描いた base を渡したときだけ作る。
//    層ごとに、アプリの描画(Renderer)を透明な下地へそのまま描く。図形はベクターなので 2 倍でも荒れない。
func heroLayers(base2x: ImageAsset) throws {
    let dir = outDir.appendingPathComponent("hero")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // 層1枚に見せる範囲(元画像の座標)。上の濃い帯から「変更を保存」まで入れる。
    // 420×280 に縮めて置く(0.42 倍)ので、線や番号はアプリの既定より太くしておく
    let sheet = rc(256, 0, 990, 660)
    let k = 2.0

    func save(_ img: CGImage, _ name: String) throws {
        try ImageExport.data(img, format: .png).write(to: dir.appendingPathComponent(name))
    }
    /// `area` の範囲を、注釈だけ(元画像なし)で描く。
    func render(_ annotations: [Annotation], area: CGRect) -> CGImage {
        let c = Renderer.makeContext(width: Int(area.width * k), height: Int(area.height * k))!
        c.scaleBy(x: k, y: k)
        c.translateBy(x: -area.minX, y: -area.minY)
        Renderer.drawAnnotations(Document(base: BaseImage(asset: base), annotations: annotations), in: c, cache: RenderCache())
        return c.makeImage()!
    }

    try save(base2x.cgImage.cropping(to: rc(sheet.minX * k, sheet.minY * k, sheet.width * k, sheet.height * k))!, "hero-base.png")
    try save(render([
        Annotation(name: "モザイク 1", content: .obscure(ObscureSpec(rect: rc(326, 325, 240, 34), mode: .pixelate, strength: 24))),
        Annotation(name: "ぼかし 1", content: .obscure(ObscureSpec(rect: rc(1124, 8, 122, 40), mode: .blur, strength: 24 * 1.4))),
    ], area: sheet), "hero-effect.png")
    try save(render([
        Annotation(name: "ハイライター 1", content: .highlighter(StrokeSpec(points: [pt(328, 539), pt(592, 539)], color: .yellow, width: 44))),
    ], area: sheet), "hero-highlight.png")
    // 矢印の尾を層の外へはみ出させるので、右へ 160 広く描く
    try save(render([
        Annotation(name: "矩形 1", content: .rect(ShapeSpec(rect: rc(304, 556, 180, 78), color: .red, width: 14))),
        Annotation(name: "スタンプ 1", content: .stamp(StampSpec(center: pt(764, 248), number: 1, color: .red, diameter: 64))),
        Annotation(name: "スタンプ 2", content: .stamp(StampSpec(center: pt(764, 342), number: 2, color: .red, diameter: 64))),
        Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: pt(1300, 320), to: pt(502, 596), color: .red, width: 48, outline: true))),
    ], area: rc(sheet.minX, sheet.minY, sheet.width + 160, sheet.height)), "hero-shapes.png")
}
if args.count > 3 {
    try heroLayers(base2x: try ImageImport.asset(contentsOf: URL(fileURLWithPath: args[3])))
}
print("ok")

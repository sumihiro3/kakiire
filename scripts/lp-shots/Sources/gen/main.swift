import CoreGraphics
import Foundation
import KakiireCore
import KakiireIO

// LP 用のサンプル文書を作る。使い方: gen [--en] <base.png> <出力フォルダ> [base@2x.png]
// --en は英語版の LP 用。元画像は mock-en.html から作り、注釈の文言とレイヤー名を英語にする
let english = CommandLine.arguments.contains("--en")
let args = CommandLine.arguments.filter { $0 != "--en" }

/// 日本語版と英語版で違うのは、文言と、英語の画面で文字の幅が変わる所の座標だけ。
struct Words: Sendable {
    var names: [String: String] = [:]
    var tip = "保存を忘れずに"
    var lastStep = "最後にここを押す"
    var draft = "あとで消す"
    var headingEnd = 468.0
    var sentenceEnd = 596.0
    var heroSentenceEnd = 592.0
    var cardSentenceEnd = 324.0
    var blur = CGRect(x: 1132, y: 10, width: 132, height: 36)
    var heroBlur = CGRect(x: 1124, y: 8, width: 122, height: 40)
    var files = ["道具の見本", "切り抜きの例", "ボタンの拡大", "手順の説明"]

    func name(_ ja: String) -> String { names[ja] ?? ja }
}
let words: Words = {
    var words = Words()
    guard english else { return words }
    words.names = [
        "モザイク 1": "Pixelate 1", "ぼかし 1": "Blur 1", "ハイライター 1": "Highlighter 1", "線 1": "Line 1",
        "楕円 1": "Ellipse 1", "矩形 1": "Rectangle 1", "ペン 1": "Pen 1", "スタンプ 1": "Stamp 1",
        "スタンプ 2": "Stamp 2", "スタンプ 3": "Stamp 3", "矢印 1": "Arrow 1", "テキスト 1": "Text 1",
        "画像 1": "Image 1", "メールを隠す": "Hide email", "保存ボタンの枠": "Save button box", "下書きのメモ": "Draft note",
    ]
    words.tip = "Don't forget!"
    words.lastStep = "Click this last"
    words.draft = "Delete later"
    // mock-en.html での文字の右端(見出し 498、説明の1文 574、右上の名前は 1125 から)
    words.headingEnd = 498
    words.sentenceEnd = 570
    words.heroSentenceEnd = 566
    words.cardSentenceEnd = 298
    words.blur = CGRect(x: 1116, y: 10, width: 148, height: 36)
    words.heroBlur = CGRect(x: 1116, y: 8, width: 130, height: 40)
    words.files = ["Tool samples", "Crop example", "Button zoom", "Steps"]
    return words
}()


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
    Annotation(name: words.name("モザイク 1"), content: .obscure(ObscureSpec(rect: rc(328, 328, 222, 30), mode: .pixelate, strength: 12))),
    Annotation(name: words.name("ぼかし 1"), content: .obscure(ObscureSpec(rect: words.blur, mode: .blur, strength: 12 * 1.4))),
    Annotation(name: words.name("ハイライター 1"), content: .highlighter(StrokeSpec(points: [pt(324, 539), pt(words.sentenceEnd, 539)], color: .yellow, width: 28))),
    Annotation(name: words.name("線 1"), content: .line(LineSpec(from: pt(289, 123), to: pt(words.headingEnd, 123), color: .blue, width: 4))),
    Annotation(name: words.name("楕円 1"), content: .ellipse(ShapeSpec(rect: rc(968, 476, 160, 60), color: .pink, width: 4))),
    Annotation(name: words.name("矩形 1"), content: .rect(ShapeSpec(rect: rc(974, 326, 244, 60), color: .red, width: 8))),
    Annotation(name: words.name("ペン 1"), content: .pen(StrokeSpec(points: check, color: .green, width: 8))),
    Annotation(name: words.name("スタンプ 1"), content: .stamp(StampSpec(center: pt(748, 248), number: 1, color: .red, diameter: 40))),
    Annotation(name: words.name("スタンプ 2"), content: .stamp(StampSpec(center: pt(748, 342), number: 2, color: .red, diameter: 40))),
    Annotation(name: words.name("矢印 1"), content: .arrow(ArrowSpec(from: pt(268, 292), to: pt(112, 236), color: .red, width: 20, outline: true))),
    Annotation(name: words.name("テキスト 1"), content: .text(TextSpec(origin: pt(322, 646), text: words.tip, color: .red, fontSize: 30))),
])
try write(tools, words.files[0] + ".kakiire")

// 切り抜きの見本用。注釈なし
try write(Document(base: BaseImage(asset: base)), words.files[1] + ".kakiire")

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
    Annotation(name: words.name("画像 1"), content: .image(ImageSpec(
        asset: zoom, rect: rc(300, 424, Double(w), Double(h)),
        border: ImageBorder(color: .red, width: 4, position: .outside), shadow: 12))),
    Annotation(name: words.name("矩形 1"), content: .rect(ShapeSpec(rect: rc(36, 404, 172, 70), color: .red, width: 4))),
    Annotation(name: words.name("矢印 1"), content: .arrow(ArrowSpec(from: pt(214, 460), to: pt(290, 488), color: .red, width: 12, outline: true))),
])
try write(overlay, words.files[2] + ".kakiire")

// 3. レイヤーの説明用(名前を付けた層、ロックした層、隠した層)
let layers = Document(base: BaseImage(asset: card), annotations: [
    Annotation(name: words.name("メールを隠す"), locked: true, content: .obscure(ObscureSpec(rect: rc(58, 174, 216, 26), mode: .pixelate, strength: 12))),
    Annotation(name: words.name("ハイライター 1"), content: .highlighter(StrokeSpec(points: [pt(52, 383), pt(words.cardSentenceEnd, 383)], color: .yellow, width: 28))),
    Annotation(name: words.name("保存ボタンの枠"), content: .rect(ShapeSpec(rect: rc(36, 404, 172, 70), color: .red, width: 8))),
    Annotation(name: words.name("スタンプ 1"), content: .stamp(StampSpec(center: pt(476, 92), number: 1, color: .red, diameter: 40))),
    Annotation(name: words.name("スタンプ 2"), content: .stamp(StampSpec(center: pt(476, 186), number: 2, color: .red, diameter: 40))),
    Annotation(name: words.name("スタンプ 3"), content: .stamp(StampSpec(center: pt(334, 550), number: 3, color: .red, diameter: 40))),
    Annotation(name: words.name("矢印 1"), content: .arrow(ArrowSpec(from: pt(332, 516), to: pt(204, 478), color: .red, width: 20, outline: true))),
    Annotation(name: words.name("テキスト 1"), content: .text(TextSpec(origin: pt(364, 532), text: words.lastStep, color: .red, fontSize: 30))),
    Annotation(name: words.name("下書きのメモ"), hidden: true, content: .text(TextSpec(origin: pt(300, 262), text: words.draft, color: .blue, fontSize: 30))),
])
try write(layers, words.files[3] + ".kakiire")

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
        Annotation(name: words.name("モザイク 1"), content: .obscure(ObscureSpec(rect: rc(326, 325, 240, 34), mode: .pixelate, strength: 24))),
        Annotation(name: words.name("ぼかし 1"), content: .obscure(ObscureSpec(rect: words.heroBlur, mode: .blur, strength: 24 * 1.4))),
    ], area: sheet), "hero-effect.png")
    try save(render([
        Annotation(name: words.name("ハイライター 1"), content: .highlighter(StrokeSpec(points: [pt(328, 539), pt(words.heroSentenceEnd, 539)], color: .yellow, width: 44))),
    ], area: sheet), "hero-highlight.png")
    // 矢印の尾を層の外へはみ出させるので、右へ 160 広く描く
    try save(render([
        Annotation(name: words.name("矩形 1"), content: .rect(ShapeSpec(rect: rc(304, 556, 180, 78), color: .red, width: 14))),
        Annotation(name: words.name("スタンプ 1"), content: .stamp(StampSpec(center: pt(764, 248), number: 1, color: .red, diameter: 64))),
        Annotation(name: words.name("スタンプ 2"), content: .stamp(StampSpec(center: pt(764, 342), number: 2, color: .red, diameter: 64))),
        Annotation(name: words.name("矢印 1"), content: .arrow(ArrowSpec(from: pt(1300, 320), to: pt(502, 596), color: .red, width: 48, outline: true))),
    ], area: rc(sheet.minX, sheet.minY, sheet.width + 160, sheet.height)), "hero-shapes.png")
}
if args.count > 3 {
    try heroLayers(base2x: try ImageImport.asset(contentsOf: URL(fileURLWithPath: args[3])))
}
print("ok")

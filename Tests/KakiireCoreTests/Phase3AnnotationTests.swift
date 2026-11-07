import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct Phase3AnnotationTests {
    let overlayImage = TestImage.noise(width: 40, height: 30, seed: 3)

    func samples() -> [Annotation] {
        [
            Annotation(name: "ハイライター 1", content: .highlighter(StrokeSpec(points: [CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 4)], color: .yellow, width: 20))),
            Annotation(name: "ペン 1", locked: true, content: .pen(StrokeSpec(points: [CGPoint(x: 5, y: 5), CGPoint(x: 6, y: 9), CGPoint(x: 12, y: 3)], color: .blue, width: 4))),
            Annotation(name: "スタンプ 1", content: .stamp(StampSpec(center: CGPoint(x: 50, y: 40), number: 3, color: .red, diameter: 32))),
            Annotation(name: "画像 1", hidden: true, content: .image(ImageSpec(asset: TestImage.asset(overlayImage), rect: CGRect(x: 10, y: 10, width: 40, height: 30)))),
        ]
    }

    @Test func jsonRoundTripWithAssets() throws {
        let anns = samples()
        let data = try JSONEncoder().encode(anns)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(json.map { $0["type"] as? String } == ["highlighter", "pen", "stamp", "image"])
        guard case .image(let im) = anns[3].content else { Issue.record(); return }
        #expect(json[3]["asset"] as? String == "assets/\(im.asset.sha256).png")

        let decoder = JSONDecoder()
        decoder.userInfo[Annotation.assetsUserInfoKey] = [im.assetPath: im.asset]
        #expect(try decoder.decode([Annotation].self, from: data) == anns)
    }

    @Test func missingAssetKeepsJSON() throws {
        let data = try JSONEncoder().encode([samples()[3]])
        let decoded = try JSONDecoder().decode([Annotation].self, from: data)
        guard case .unknown(let type, _) = decoded[0].content else { Issue.record(); return }
        #expect(type == "image")
        // 再保存しても消えない。
        let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [[String: Any]]
        #expect(again[0]["asset"] as? String != nil)
    }

    @Test func movingAndHitTesting() {
        let anns = samples()
        let doc = TestImage.document(TestImage.noise(width: 100, height: 80), anns)
        let moved = doc.applying(.move(Set(anns.map(\.id)), by: CGVector(dx: 10, dy: 0)))
        guard case .highlighter(let h) = moved.annotations[0].content, case .pen(let p) = moved.annotations[1].content,
              case .stamp(let s) = moved.annotations[2].content else { Issue.record(); return }
        #expect(h.points[0] == CGPoint(x: 11, y: 2))
        #expect(p.points[0] == CGPoint(x: 5, y: 5), "locked pen stays")
        #expect(s.center == CGPoint(x: 60, y: 40))
        #expect(HitTesting.annotation(at: CGPoint(x: 15, y: 3), in: doc, tolerance: 1) == anns[0].id)
        #expect(HitTesting.annotation(at: CGPoint(x: 60, y: 40), in: doc, tolerance: 1) == anns[2].id)
        #expect(HitTesting.annotation(at: CGPoint(x: 90, y: 70), in: doc, tolerance: 1) == nil)
    }

    @Test func imageCornerKeepsAspect() {
        let a = samples()[3]
        let r = a.resized(.bottomRight, to: CGPoint(x: 90, y: 20))
        guard case .image(let im) = r.content else { Issue.record(); return }
        #expect(im.rect == CGRect(x: 10, y: 10, width: 80, height: 60))
        guard case .image(let free) = a.resized(.bottomRight, to: CGPoint(x: 90, y: 20), constrain: true).content else { Issue.record(); return }
        #expect(free.rect == CGRect(x: 10, y: 10, width: 80, height: 10))
    }

    @Test func nextStampNumberIsMaxPlusOne() {
        func stamp(_ n: Int) -> Annotation {
            Annotation(name: "s", content: .stamp(StampSpec(center: .zero, number: n, color: .red, diameter: 10)))
        }
        #expect(TestImage.document(overlayImage).nextStampNumber == 1)
        #expect(TestImage.document(overlayImage, [stamp(1), stamp(3)]).nextStampNumber == 4)
    }

    @Test func highlighterMultipliesOverDarkPixels() throws {
        // 黒い上に塗っても黒のまま(下の文字を潰さない)、白い上は塗った色になる。
        var px = [UInt8](repeating: 255, count: 40 * 20 * 4)
        for y in 0..<20 { for x in 0..<20 { let i = (y * 40 + x) * 4; px[i] = 0; px[i + 1] = 0; px[i + 2] = 0 } }
        let base = TestImage.make(px, 40, 20)
        let h = Annotation(name: "h", content: .highlighter(StrokeSpec(points: [CGPoint(x: 0, y: 10), CGPoint(x: 40, y: 10)], color: .yellow, width: 10)))
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(base, [h]))))
        #expect(out.rgba(10, 10) == [0, 0, 0, 255])
        let y = RGBAColor.yellow
        #expect(out.rgba(30, 10) == [y.r, y.g, y.b, 255])
    }

    @Test func highlighterIsBelowShapesAndAboveEffects() throws {
        let white = TestImage.solid(width: 40, height: 20, .white)
        let line = Annotation(name: "l", content: .line(LineSpec(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 40, y: 10), color: .blue, width: 4)))
        let h = Annotation(name: "h", content: .highlighter(StrokeSpec(points: [CGPoint(x: 0, y: 10), CGPoint(x: 40, y: 10)], color: .yellow, width: 10)))
        // 配列ではハイライターを前面に置いても、線は上に描かれる。
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [line, h]))))
        let b = RGBAColor.blue
        #expect(out.rgba(20, 10) == [b.r, b.g, b.b, 255])
    }

    /// 仕様:モザイクは元画像と画像オーバーレイを合わせたものから計算する。貼った画像の 8×8 ブロックも残らない。
    @Test func obscureCoversImageOverlay() throws {
        let base = TestImage.solid(width: 120, height: 90, .white)
        let overlay = Annotation(name: "i", content: .image(ImageSpec(asset: TestImage.asset(overlayImage), rect: CGRect(x: 20, y: 20, width: 40, height: 30))))
        let mosaic = Annotation(name: "m", content: .obscure(ObscureSpec(rect: CGRect(x: 0, y: 0, width: 120, height: 90), mode: .pixelate, strength: 12)))
        // 画像を配列で前面に置いても、効果より下に描かれる。
        let doc = TestImage.document(base, [mosaic, overlay])
        let out = Pixels(try #require(Renderer.makeImage(doc)))
        let src = Pixels(overlayImage)
        for by in 0...(src.height - 8) {
            for bx in 0...(src.width - 8) {
                var same = true
                outer: for y in by..<(by + 8) {
                    for x in bx..<(bx + 8) where out.rgba(x + 20, y + 20) != src.rgba(x, y) { same = false; break outer }
                }
                #expect(!same, "overlay block at (\(bx),\(by)) survived")
            }
        }
        // 画像がない所は白のまま(モザイクしても白)。
        #expect(out.rgba(100, 80) == [255, 255, 255, 255])
    }

    @Test func effectCacheFollowsOverlayMoves() throws {
        let cache = RenderCache()
        let base = TestImage.solid(width: 120, height: 90, .white)
        let overlay = Annotation(name: "i", content: .image(ImageSpec(asset: TestImage.asset(TestImage.solid(width: 20, height: 20, .black)), rect: CGRect(x: 0, y: 0, width: 20, height: 20))))
        let mosaic = Annotation(name: "m", content: .obscure(ObscureSpec(rect: CGRect(x: 0, y: 0, width: 120, height: 90), mode: .pixelate, strength: 10)))
        let doc = TestImage.document(base, [overlay, mosaic])
        _ = Renderer.makeImage(doc, cache: cache)
        let moved = doc.applying(.move([overlay.id], by: CGVector(dx: 60, dy: 40)))
        let out = Pixels(try #require(Renderer.makeImage(moved, cache: cache)))
        #expect(out.rgba(5, 5) == [255, 255, 255, 255])
        #expect(out.rgba(65, 45)[0] < 50)
    }

    @Test func stampDrawsNumberInside() throws {
        let white = TestImage.solid(width: 60, height: 60, .white)
        let s = Annotation(name: "s", content: .stamp(StampSpec(center: CGPoint(x: 30, y: 30), number: 1, color: .blue, diameter: 40)))
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [s]))))
        // 丸の内側に、塗り色と白い文字の両方がある。
        var whiteInside = 0, blueInside = 0
        for y in 20..<40 { for x in 20..<40 {
            let p = out.rgba(x, y)
            if p[0] > 240 && p[1] > 240 && p[2] > 240 { whiteInside += 1 }
            if p == [RGBAColor.blue.r, RGBAColor.blue.g, RGBAColor.blue.b, 255] { blueInside += 1 }
        } }
        #expect(whiteInside > 10 && blueInside > 100)
        #expect(out.rgba(2, 2) == [255, 255, 255, 255])
    }
}

@Suite struct LayerListTests {
    let img = TestImage.noise(width: 10, height: 10)

    func a(_ name: String, _ c: AnnotationContent) -> Annotation { Annotation(name: name, content: c) }
    var shape: AnnotationContent { .rect(ShapeSpec(rect: CGRect(x: 0, y: 0, width: 2, height: 2), color: .red, width: 1)) }
    var effect: AnnotationContent { .obscure(ObscureSpec(rect: CGRect(x: 0, y: 0, width: 2, height: 2), mode: .pixelate, strength: 4)) }

    @Test func rowsGroupFrontFirst() {
        let s1 = a("s1", shape), e1 = a("e1", effect), s2 = a("s2", shape), e2 = a("e2", effect)
        let doc = TestImage.document(img, [s1, e1, s2, e2])
        #expect(LayerList.rows(doc) == [s2.id, s1.id, e2.id, e1.id])
    }

    @Test func moveWithinGroupMapsToArray() throws {
        let s1 = a("s1", shape), e1 = a("e1", effect), s2 = a("s2", shape), s3 = a("s3", shape)
        let doc = TestImage.document(img, [s1, e1, s2, s3])
        // パネル:[s3, s2, s1, e1]。s1 を一番上へ。
        let op = try #require(LayerList.move(s1.id, toRow: 0, in: doc))
        let moved = doc.applying(op)
        #expect(LayerList.rows(moved) == [s1.id, s3.id, s2.id, e1.id])
        // s3 を s1 の下(行 3 の手前)へ。
        let op2 = try #require(LayerList.move(s3.id, toRow: 3, in: doc))
        #expect(LayerList.rows(doc.applying(op2)) == [s2.id, s1.id, s3.id, e1.id])
    }

    @Test func cannotMoveAcrossGroups() {
        let s1 = a("s1", shape), e1 = a("e1", effect), e2 = a("e2", effect)
        let doc = TestImage.document(img, [s1, e1, e2])
        // パネル:[s1, e2, e1]。e1 を図形の上へは入れない。
        #expect(LayerList.move(e1.id, toRow: 0, in: doc) == nil)
        #expect(LayerList.move(s1.id, toRow: 3, in: doc) == nil)
        #expect(LayerList.move(e1.id, toRow: 1, in: doc) != nil)
        #expect(LayerList.move(e1.id, toRow: 3, in: doc) == nil, "already last: no-op")
    }

    /// 後から貼った画像が配列で前にあっても、上に描かれる矢印がクリックで選ばれる。
    @Test func hitTestFollowsRenderOrder() {
        let arrow = a("arrow", .arrow(ArrowSpec(from: CGPoint(x: 1, y: 5), to: CGPoint(x: 9, y: 5), color: .red, width: 2)))
        let image = a("image", .image(ImageSpec(asset: TestImage.asset(img), rect: CGRect(x: 0, y: 0, width: 10, height: 10))))
        let doc = TestImage.document(img, [arrow, image])
        #expect(HitTesting.annotation(at: CGPoint(x: 5, y: 5), in: doc, tolerance: 1) == arrow.id)
        #expect(HitTesting.annotation(at: CGPoint(x: 5, y: 9), in: doc, tolerance: 0) == image.id)
    }

    /// 複数を最背面へ送るときは前面側から動かすと、相対順が保たれる。
    @Test func sendSeveralToBackKeepsOrder() throws {
        let s1 = a("s1", shape), s2 = a("s2", shape), s3 = a("s3", shape)
        var doc = TestImage.document(img, [s1, s2, s3])
        for id in LayerList.rows(doc).filter([s2.id, s3.id].contains) {
            doc = doc.applying(try #require(LayerList.moveToBack(id, in: doc)))
        }
        #expect(doc.annotations.map(\.id) == [s2.id, s3.id, s1.id])
    }

    @Test func frontAndBack() throws {
        let s1 = a("s1", shape), s2 = a("s2", shape), s3 = a("s3", shape)
        let doc = TestImage.document(img, [s1, s2, s3])
        #expect(doc.applying(try #require(LayerList.moveToFront(s1.id, in: doc))).annotations.last?.id == s1.id)
        #expect(doc.applying(try #require(LayerList.moveToBack(s3.id, in: doc))).annotations.first?.id == s3.id)
    }
}

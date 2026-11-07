import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct RenderTests {
    let noise = TestImage.noise(width: 160, height: 120)

    func obscure(_ r: CGRect, _ mode: ObscureMode = .pixelate, strength: Double = 12) -> Annotation {
        Annotation(name: "o", content: .obscure(ObscureSpec(rect: r, mode: mode, strength: strength)))
    }

    @Test(arguments: [ObscureMode.pixelate, .blur])
    func obscureChangesOnlyItsRegion(mode: ObscureMode) throws {
        let region = CGRect(x: 40, y: 30, width: 64, height: 48)
        let doc = TestImage.document(noise, [obscure(region, mode)])
        let out = Pixels(try #require(Renderer.makeImage(doc)))
        let src = Pixels(noise)

        var changedInside = 0
        for y in 0..<src.height {
            for x in 0..<src.width {
                let inside = region.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                if inside {
                    if out.rgba(x, y) != src.rgba(x, y) { changedInside += 1 }
                } else {
                    #expect(out.rgba(x, y) == src.rgba(x, y), "outside pixel (\(x),\(y)) changed")
                }
            }
        }
        #expect(changedInside > Int(region.width * region.height) * 9 / 10)
    }

    /// 完了条件②:伏せた範囲のどの 8×8 ブロックも元画像と一致しない。
    @Test(arguments: [ObscureMode.pixelate, .blur])
    func noOriginalBlockSurvives(mode: ObscureMode) throws {
        let region = CGRect(x: 16, y: 16, width: 96, height: 80)
        let doc = TestImage.document(noise, [obscure(region, mode)])
        let out = Pixels(try #require(Renderer.makeImage(doc)))
        let src = Pixels(noise)
        for by in stride(from: Int(region.minY), through: Int(region.maxY) - 8, by: 1) {
            for bx in stride(from: Int(region.minX), through: Int(region.maxX) - 8, by: 4) {
                var same = true
                outer: for y in by..<(by + 8) {
                    for x in bx..<(bx + 8) where out.rgba(x, y) != src.rgba(x, y) { same = false; break outer }
                }
                #expect(!same, "8x8 block at (\(bx),\(by)) equals the original")
            }
        }
    }

    @Test func shapesAreDrawnAboveEffectsRegardlessOfOrder() throws {
        let line = Annotation(name: "l", content: .line(LineSpec(from: CGPoint(x: 0, y: 60), to: CGPoint(x: 160, y: 60), color: .blue, width: 6)))
        // モザイクを配列で後ろ(前面)に置いても、線は上に描かれる。
        let doc = TestImage.document(noise, [line, obscure(CGRect(x: 20, y: 20, width: 100, height: 80))])
        let out = Pixels(try #require(Renderer.makeImage(doc)))
        #expect(out.rgba(70, 60) == [RGBAColor.blue.r, RGBAColor.blue.g, RGBAColor.blue.b, 255])
    }

    @Test func hiddenIsNotDrawn() throws {
        var r = Annotation(name: "r", content: .rect(ShapeSpec(rect: CGRect(x: 0, y: 0, width: 50, height: 50), color: .red, width: 4, fill: .red)))
        r.hidden = true
        let white = TestImage.solid(width: 60, height: 60, .white)
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [r]))))
        #expect(out.rgba(25, 25) == [255, 255, 255, 255])
    }

    @Test func cropAndOutputScale() throws {
        var doc = TestImage.document(noise)
        doc.canvas = Canvas(crop: CGRect(x: 10, y: 10, width: 100, height: 60), outputScale: 0.5)
        let img = try #require(Renderer.makeImage(doc))
        #expect(img.width == 50 && img.height == 30)
    }

    @Test func taperedArrowCoversTipAndTail() throws {
        let a = Annotation(name: "a", content: .arrow(ArrowSpec(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 150, y: 50), color: .pink, width: 12)))
        let white = TestImage.solid(width: 160, height: 100, .white)
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [a]))))
        let pink: [UInt8] = [RGBAColor.pink.r, RGBAColor.pink.g, RGBAColor.pink.b, 255]
        #expect(out.rgba(12, 50) == pink)   // 尾
        #expect(out.rgba(140, 50) == pink)  // 矢じり
        #expect(out.rgba(112, 50 - 12) == pink) // 矢じりの根元は首より幅広い
        #expect(out.rgba(100, 50 - 5) == [255, 255, 255, 255]) // 首は細い
    }

    @Test func textDrawsInsideItsBounds() throws {
        let spec = TextSpec(origin: CGPoint(x: 10, y: 10), text: "Kakiire", color: .blue, fontSize: 28)
        let t = Annotation(name: "t", content: .text(spec))
        let white = TestImage.solid(width: 200, height: 80, .white)
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [t]))))
        let b = TextLayout.bounds(spec)
        var blue = 0, outsideInk = 0
        for y in 0..<out.height {
            for x in 0..<out.width where out.rgba(x, y) != [255, 255, 255, 255] {
                if b.contains(CGPoint(x: x, y: y)) {
                    if out.rgba(x, y) == [RGBAColor.blue.r, RGBAColor.blue.g, RGBAColor.blue.b, 255] { blue += 1 }
                } else { outsideInk += 1 }
            }
        }
        #expect(blue > 50)
        #expect(outsideInk == 0)
    }

    @Test func rotation90MovesPixelsClockwise() throws {
        // 左上だけ赤い 4×2 画像を時計回りに 90° 回すと、2×4 の右上が赤になる。
        var px = [UInt8](repeating: 255, count: 4 * 2 * 4)
        px[0] = 255; px[1] = 0; px[2] = 0
        let img = TestImage.make(px, 4, 2)
        var doc = TestImage.document(img)
        doc.base.rotation = .r90
        let out = Pixels(try #require(Renderer.makeImage(doc)))
        #expect(out.width == 2 && out.height == 4)
        #expect(out.rgba(1, 0) == [255, 0, 0, 255])
        #expect(out.rgba(0, 0) == [255, 255, 255, 255])
    }

    @Test func effectCacheIsReused() {
        let cache = RenderCache()
        let doc = TestImage.document(noise, [obscure(CGRect(x: 0, y: 0, width: 40, height: 40))])
        let ctx = Renderer.makeContext(width: 160, height: 120)!
        var made = 0
        let key = RenderCache.EffectKey(base: RenderCache.key(doc.base), region: PixelRect(x: 0, y: 0, width: 40, height: 40), mode: .pixelate, strength: 12)
        Renderer.drawAnnotations(doc, in: ctx, cache: cache)
        _ = cache.effect(key) { made += 1; return nil }
        #expect(made == 0)
    }

    /// 完了条件③の目安:4K に注釈20個。効果がキャッシュ済みなら1フレームの描画は十分速い。
    @Test func performance4K() throws {
        let big = TestImage.noise(width: 3840, height: 2160)
        var anns: [Annotation] = []
        for i in 0..<17 {
            let x = CGFloat(100 + i * 200)
            anns.append(Annotation(name: "a\(i)", content: .arrow(ArrowSpec(from: CGPoint(x: x, y: 200), to: CGPoint(x: x + 150, y: 900), color: .pink, width: 10))))
        }
        for i in 0..<3 {
            anns.append(obscure(CGRect(x: 300 + i * 1100, y: 1200, width: 800, height: 400)))
        }
        let doc = TestImage.document(big, anns)
        let cache = RenderCache()
        let ctx = Renderer.makeContext(width: 3840, height: 2160)!

        let clock = ContinuousClock()
        let cold = clock.measure { Renderer.drawAnnotations(doc, in: ctx, cache: cache) }
        var warm = Duration.zero
        for _ in 0..<10 { warm += clock.measure { Renderer.drawAnnotations(doc, in: ctx, cache: cache) } }
        let warmMs = Double(warm.components.attoseconds) / 1e15 / 10 + Double(warm.components.seconds) * 100
        print("performance4K: cold=\(cold) warm(avg)=\(warmMs)ms")
        #expect(warmMs < 100)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

/// 画像オーバーレイの枠線と影。
@Suite struct ImageFrameTests {
    let inner = TestImage.solid(width: 60, height: 40, .white)
    let rect = CGRect(x: 40, y: 30, width: 60, height: 40)

    func overlay(border: ImageBorder? = nil, shadow: Double = 0) -> Annotation {
        Annotation(name: "i", content: .image(ImageSpec(asset: TestImage.asset(inner), rect: rect, border: border, shadow: shadow)))
    }

    func decoder(_ a: Annotation) -> JSONDecoder {
        guard case .image(let im) = a.content else { return JSONDecoder() }
        let d = JSONDecoder()
        d.userInfo[Annotation.assetsUserInfoKey] = [im.assetPath: im.asset]
        return d
    }

    @Test func defaultsAreNoFrame() {
        let s = ImageSpec(asset: TestImage.asset(inner), rect: rect)
        #expect(s.border == nil && s.shadow == 0)
    }

    @Test func roundTripsAndOmitsDefaults() throws {
        let on = overlay(border: ImageBorder(color: .blue, width: 4), shadow: 10)
        let data = try JSONEncoder().encode([on])
        #expect(try decoder(on).decode([Annotation].self, from: data) == [on])

        let off = overlay()
        let offJSON = String(decoding: try JSONEncoder().encode([off]), as: UTF8.self)
        #expect(!offJSON.contains("border") && !offJSON.contains("shadow"))
        #expect(try decoder(off).decode([Annotation].self, from: JSONEncoder().encode([off])) == [off])
    }

    @Test func shadowWidensDrawnBoundsButNotHitArea() {
        #expect(overlay().bounds == rect)
        let s = overlay(shadow: 10)
        #expect(s.bounds.contains(rect))
        #expect(s.bounds.maxY > rect.maxY + 10)
        let doc = TestImage.document(TestImage.solid(width: 200, height: 150, .black), [s])
        #expect(HitTesting.annotation(at: CGPoint(x: rect.midX, y: rect.maxY + 6), in: doc, tolerance: 1) == nil)
    }

    @Test func borderIsDrawnInsideTheImage() throws {
        let doc = TestImage.document(TestImage.solid(width: 200, height: 150, .black),
                                     [overlay(border: ImageBorder(color: .blue, width: 4))])
        let px = Pixels(try #require(Renderer.makeImage(doc)))
        let edge = px.rgba(Int(rect.minX) + 1, Int(rect.midY))
        #expect(edge[2] > 200 && edge[0] < 80, "inner edge is blue")
        let outside = px.rgba(Int(rect.minX) - 2, Int(rect.midY))
        #expect(outside[0] < 40 && outside[2] < 40, "outside stays black")
        let center = px.rgba(Int(rect.midX), Int(rect.midY))
        #expect(center[0] > 230 && center[2] > 230, "image itself is untouched")
    }

    @Test func shadowDarkensBelowTheImage() throws {
        let white = TestImage.solid(width: 200, height: 150, .white)
        let plain = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [overlay(border: ImageBorder(color: .red, width: 2))]))))
        let shadowed = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [overlay(border: ImageBorder(color: .red, width: 2), shadow: 10)]))))
        let below = (Int(rect.midX), Int(rect.maxY) + 3)
        #expect(plain.rgba(below.0, below.1)[0] > 250)
        #expect(shadowed.rgba(below.0, below.1)[0] < 235)
    }

    @Test func mosaicSeesTheBorder() throws {
        // 枠線は効果の合成にも入る(モザイクの下で枠が消えたり、ずれたりしない)。
        let white = TestImage.solid(width: 200, height: 150, .white)
        let framed = overlay(border: ImageBorder(color: .blue, width: 8))
        let mosaic = Annotation(name: "m", content: .obscure(ObscureSpec(rect: CGRect(x: 30, y: 20, width: 40, height: 60), mode: .pixelate, strength: 4)))
        let px = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [framed, mosaic]))))
        let p = px.rgba(Int(rect.minX) + 2, Int(rect.midY))
        #expect(p[2] > p[0] + 60, "blue survives under the mosaic")
    }

    @Test func outsideBorderIsDrawnAroundTheImage() throws {
        let border = ImageBorder(color: .blue, width: 4, position: .outside)
        let doc = TestImage.document(TestImage.solid(width: 200, height: 150, .black), [overlay(border: border)])
        let px = Pixels(try #require(Renderer.makeImage(doc)))
        let out = px.rgba(Int(rect.minX) - 2, Int(rect.midY))
        #expect(out[2] > 200 && out[0] < 80, "just outside is blue")
        let inner = px.rgba(Int(rect.minX) + 1, Int(rect.midY))
        #expect(inner[0] > 230 && inner[2] > 230, "image edge is not covered")
    }

    @Test func outsideBorderWidensDrawnBounds() {
        #expect(overlay(border: ImageBorder(color: .blue, width: 4)).bounds == rect)
        #expect(overlay(border: ImageBorder(color: .blue, width: 4, position: .outside)).bounds == rect.insetBy(dx: -4, dy: -4))
    }

    @Test func borderPositionRoundTripsAndInsideIsOmitted() throws {
        let outside = overlay(border: ImageBorder(color: .blue, width: 4, position: .outside))
        #expect(try decoder(outside).decode([Annotation].self, from: JSONEncoder().encode([outside])) == [outside])
        #expect(String(decoding: try JSONEncoder().encode([outside]), as: UTF8.self).contains("\"borderPosition\":\"outside\""))
        let inside = overlay(border: ImageBorder(color: .blue, width: 4))
        #expect(!String(decoding: try JSONEncoder().encode([inside]), as: UTF8.self).contains("borderPosition"))
    }
}

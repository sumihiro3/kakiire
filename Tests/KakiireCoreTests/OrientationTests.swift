import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct OrientationTests {
    /// 縦横で値が違う、向きの分かる画像(5×3)。
    let image = TestImage.noise(width: 5, height: 3, seed: 7)

    static let allStates: [(Rotation, Bool, Bool)] = Rotation.allCases.flatMap { r in
        [(r, false, false), (r, true, false), (r, false, true), (r, true, true)]
    }
    static let transforms: [ImageTransform] = [.rotateClockwise, .rotateCounterclockwise, .flipHorizontal, .flipVertical]

    /// 画像 `p` に `t` をかけた画素(テスト用の素朴な実装)。
    func reference(_ p: Pixels, _ t: ImageTransform) -> [[UInt8]] {
        let size = CGSize(width: p.width, height: p.height)
        let outW = t.swapsAxes ? p.height : p.width, outH = t.swapsAxes ? p.width : p.height
        var out = [[UInt8]](repeating: [], count: outW * outH)
        for y in 0..<p.height {
            for x in 0..<p.width {
                // 画素の中心を移し、移った先の画素に置く。
                let q = t.apply(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), in: size)
                out[Int(q.y) * outW + Int(q.x)] = p.rgba(x, y)
            }
        }
        return out
    }

    func pixels(_ p: Pixels) -> [[UInt8]] {
        (0..<p.height).flatMap { y in (0..<p.width).map { x in p.rgba(x, y) } }
    }

    /// 8(+重複)の開始状態すべてで、「文書を変換してから描く」と「描いてから変換する」が画素で一致する。
    @Test(arguments: transforms)
    func composesLikeTheImage(t: ImageTransform) throws {
        for (r, h, v) in Self.allStates {
            var doc = TestImage.document(image)
            doc.base = BaseImage(asset: doc.base.asset, rotation: r, flipH: h, flipV: v)
            let before = Pixels(try #require(Renderer.makeImage(doc)))
            let after = Pixels(try #require(Renderer.makeImage(doc.applying(.transform(t)))))
            #expect(pixels(after) == reference(before, t), "state \(r) h=\(h) v=\(v) then \(t)")
        }
    }

    @Test func fourQuarterTurnsAreIdentity() throws {
        let arrow = Annotation(name: "a", content: .arrow(ArrowSpec(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 4, y: 1), color: .red, width: 2)))
        let rect = Annotation(name: "r", content: .rect(ShapeSpec(rect: CGRect(x: 1, y: 0, width: 2, height: 3), color: .red, width: 1)))
        let pen = Annotation(name: "p", content: .pen(StrokeSpec(points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 3)], color: .red, width: 1)))
        let text = Annotation(name: "t", content: .text(TextSpec(origin: CGPoint(x: 2, y: 1), text: "A", color: .red, fontSize: 4)))
        var doc = TestImage.document(image, [arrow, rect, pen, text])
        doc.canvas.crop = CGRect(x: 1, y: 1, width: 3, height: 2)
        var d = doc
        for _ in 0..<4 { d = d.applying(.transform(.rotateClockwise)) }
        #expect(d.base == doc.base)
        #expect(d.canvas == doc.canvas)
        #expect(d.annotations.prefix(3) == doc.annotations.prefix(3))
        guard case .text(let t0) = doc.annotations[3].content, case .text(let t1) = d.annotations[3].content else { Issue.record(); return }
        #expect(abs(t0.origin.x - t1.origin.x) < 1e-9 && abs(t0.origin.y - t1.origin.y) < 1e-9)
    }

    @Test func flipTwiceIsIdentity() {
        let doc = TestImage.document(image, [Annotation(name: "s", content: .stamp(StampSpec(center: CGPoint(x: 1, y: 1), number: 1, color: .red, diameter: 2)))])
        for t in [ImageTransform.flipHorizontal, .flipVertical] {
            #expect(doc.applying([.transform(t), .transform(t)]) == doc)
        }
    }

    @Test func annotationsFollowRotation() {
        let line = Annotation(name: "l", content: .line(LineSpec(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 0), color: .red, width: 1)))
        let doc = TestImage.document(image, [line]).applying(.transform(.rotateClockwise))
        #expect(doc.pixelSize == CGSize(width: 3, height: 5))
        // 上辺の線は、右に回すと右辺になる。
        guard case .line(let l) = doc.annotations[0].content else { Issue.record(); return }
        #expect(l.from == CGPoint(x: 3, y: 0) && l.to == CGPoint(x: 3, y: 5))
    }

    @Test func stampStaysUpright() {
        let st = Annotation(name: "s", content: .stamp(StampSpec(center: CGPoint(x: 1, y: 1), number: 1, color: .red, diameter: 2)))
        let doc = TestImage.document(TestImage.noise(width: 10, height: 6), [st]).applying(.transform(.rotateClockwise))
        guard case .stamp(let s) = doc.annotations[0].content else { Issue.record(); return }
        #expect(s.center == CGPoint(x: 5, y: 1))
        #expect(s.diameter == 2)
    }

    /// 画像オーバーレイは中身ごと回る。上に掛けたモザイクとずれて、伏せた内容が見えてしまわないように。
    @Test(arguments: transforms)
    func overlayUnderMosaicStaysCovered(t: ImageTransform) throws {
        let base = TestImage.solid(width: 60, height: 40, .white)
        let secret = TestImage.noise(width: 30, height: 10, seed: 11)
        let overlay = Annotation(name: "i", content: .image(ImageSpec(asset: TestImage.asset(secret), rect: CGRect(x: 10, y: 5, width: 30, height: 10))))
        let mosaic = Annotation(name: "m", content: .obscure(ObscureSpec(rect: CGRect(x: 10, y: 5, width: 30, height: 10), mode: .pixelate, strength: 10)))
        let doc = TestImage.document(base, [overlay, mosaic])
        let before = Pixels(try #require(Renderer.makeImage(doc)))
        let after = Pixels(try #require(Renderer.makeImage(doc.applying(.transform(t)))))
        // 回した後の画像は、回す前の画像を回したものと画素で一致する(=モザイクの外に中身が出ない)。
        #expect(pixels(after) == reference(before, t))
    }

    @Test func cropAndScaleAreClampedAndNonDestructive() {
        let doc = TestImage.document(image)
        let cropped = doc.applying(.setCrop(CGRect(x: 3, y: -1, width: 10, height: 2)))
        #expect(cropped.canvas.crop == CGRect(x: 3, y: 0, width: 2, height: 1))
        #expect(cropped.base == doc.base)
        #expect(cropped.applying(.setCrop(nil)) == doc)
        #expect(doc.applying(.setCrop(CGRect(x: 0, y: 0, width: 5, height: 3))).canvas.crop == nil)
        #expect(doc.applying(.setOutputScale(0.5)).canvas.outputScale == 0.5)
        #expect(doc.applying(.setOutputScale(-1)).canvas.outputScale == 1)
    }

    @Test func outputScaleShrinksStrokesToo() throws {
        // ADR 0001:線幅は画像と一緒に縮む。
        let white = TestImage.solid(width: 100, height: 100, .white)
        let line = Annotation(name: "l", content: .line(LineSpec(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), color: .black, width: 20)))
        var doc = TestImage.document(white, [line])
        doc.canvas.outputScale = 0.5
        let out = Pixels(try #require(Renderer.makeImage(doc)))
        let dark = (0..<out.height).filter { out.rgba(25, $0)[0] < 128 }.count
        #expect(dark == 10)
    }
}

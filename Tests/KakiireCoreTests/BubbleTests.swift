import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct BubbleTests {
    static func spec(_ shape: BubbleShape = .rounded, color: RGBAColor = .blue,
                     tail: CGPoint = CGPoint(x: 20, y: 150)) -> BubbleSpec {
        BubbleSpec(origin: CGPoint(x: 60, y: 30), text: "Hi\nKakiire", color: color, fontSize: 24, shape: shape, tail: tail)
    }

    static func bubble(_ s: BubbleSpec) -> Annotation { Annotation(name: "b", content: .bubble(s)) }

    @Test(arguments: BubbleShape.allCases)
    func roundTrips(shape: BubbleShape) throws {
        var s = Self.spec(shape)
        s.bold = false
        let a = Self.bubble(s)
        let back = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(a))
        #expect(back == a)
    }

    @Test func defaultsAreNotWritten() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.bubble(Self.spec()))) as! [String: Any]
        let style = json["style"] as! [String: Any]
        #expect(json["type"] as? String == "bubble")
        #expect(style["shape"] == nil && style["bold"] == nil)
        #expect((json["geometry"] as! [String: Any])["tail"] as? [Double] == [20, 150])
    }

    @Test func missingShapeReadsAsRounded() throws {
        let json = ##"{"type":"bubble","geometry":{"origin":[1,2],"tail":[3,4]},"style":{"color":"#0000FF","fontSize":20,"shape":"heart"},"text":"x"}"##
        let a = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        guard case .bubble(let b) = a.content else { Issue.record(); return }
        #expect(b.shape == .rounded && b.bold && b.text == "x")
    }

    @Test(arguments: BubbleShape.allCases)
    func bodyHoldsTextAndBoundsHoldTail(shape: BubbleShape) {
        let s = Self.spec(shape)
        let body = BubbleLayout.body(s)
        let tb = BubbleLayout.textBox(s)
        for p in [CGPoint(x: tb.minX, y: tb.minY), CGPoint(x: tb.maxX, y: tb.minY),
                  CGPoint(x: tb.minX, y: tb.maxY), CGPoint(x: tb.maxX, y: tb.maxY)] {
            #expect(body.contains(p), "\(shape) corner \(p)")
        }
        #expect(BubbleLayout.bounds(s).contains(s.tail))
        #expect(!BubbleLayout.bodyRect(s).contains(s.tail))
    }

    @Test func tailInsideBodyDrawsNoTail() {
        var s = Self.spec()
        s.tail = BubbleLayout.textBox(s).center
        #expect(BubbleLayout.outline(s).boundingBoxOfPath == BubbleLayout.bodyRect(s))
    }

    @Test(arguments: BubbleShape.allCases)
    func hitsTailButNotEmptySpace(shape: BubbleShape) {
        let a = Self.bubble(Self.spec(shape))
        guard case .bubble(let s) = a.content else { return }
        // 先の少し手前(しっぽの上)は当たり、本体から離れた所は当たらない。
        let near = s.tail + (BubbleLayout.bodyRect(s).center - s.tail) * 0.05
        #expect(HitTesting.hits(a, near, 2))
        #expect(HitTesting.hits(a, BubbleLayout.textBox(s).center, 2))
        #expect(!HitTesting.hits(a, CGPoint(x: 300, y: 10), 2))
    }

    @Test func handlesAreBodyCornersAndTail() {
        let s = Self.spec()
        let a = Self.bubble(s)
        let r = BubbleLayout.bodyRect(s)
        #expect(a.handles.map(\.0) == [.topLeft, .topRight, .bottomRight, .bottomLeft, .tail])
        #expect(a.handles.first { $0.0 == .bottomRight }?.1 == CGPoint(x: r.maxX, y: r.maxY))
        #expect(a.handles.last?.1 == s.tail)
    }

    @Test func tailHandleMovesOnlyTheTail() {
        let a = Self.bubble(Self.spec())
        guard case .bubble(let b) = a.resized(.tail, to: CGPoint(x: 300, y: 5)).content else { Issue.record(); return }
        #expect(b.tail == CGPoint(x: 300, y: 5))
        #expect(b.origin == Self.spec().origin && b.fontSize == 24)
    }

    @Test func cornerScalesFontAroundOppositeCorner() {
        let s = Self.spec()
        let r = BubbleLayout.bodyRect(s)
        let a = Self.bubble(s).resized(.bottomRight, to: CGPoint(x: r.minX + r.width * 2, y: r.minY + r.height * 2))
        guard case .bubble(let b) = a.content else { Issue.record(); return }
        let nr = BubbleLayout.bodyRect(b)
        #expect(b.fontSize > 40)
        #expect(abs(nr.minX - r.minX) < 0.5 && abs(nr.minY - r.minY) < 0.5)
        #expect(b.tail == s.tail)
    }

    @Test func moveCarriesTail() {
        guard case .bubble(let b) = Self.bubble(Self.spec()).moved(by: CGVector(dx: 5, dy: -3)).content else { Issue.record(); return }
        #expect(b.origin == CGPoint(x: 65, y: 27) && b.tail == CGPoint(x: 25, y: 147))
    }

    @Test func frameIsTheBodyWithoutTail() {
        let s = Self.spec()
        #expect(Self.bubble(s).frame == BubbleLayout.bodyRect(s))
    }

    @Test func rotationKeepsBodyUprightAndTurnsTail() {
        let doc = TestImage.document(TestImage.solid(width: 300, height: 200, .white), [Self.bubble(Self.spec())])
        let turned = doc.applying(.transform(.rotateClockwise))
        guard case .bubble(let b) = turned.annotations[0].content else { Issue.record(); return }
        // 時計回り:(x, y) → (H - y, x)
        #expect(b.tail == CGPoint(x: 200 - 150, y: 20))
        #expect(b.fontSize == 24 && b.text == "Hi\nKakiire")
        let c0 = BubbleLayout.bodyRect(Self.spec()).center, c1 = BubbleLayout.bodyRect(b).center
        #expect(abs(c1.x - (200 - c0.y)) < 1e-6 && abs(c1.y - c0.x) < 1e-6)

        var d = doc
        for _ in 0..<4 { d = d.applying(.transform(.rotateClockwise)) }
        guard case .bubble(let back) = d.annotations[0].content else { Issue.record(); return }
        #expect(abs(back.origin.x - 60) < 1e-6 && abs(back.origin.y - 30) < 1e-6 && back.tail == Self.spec().tail)
    }

    @Test(arguments: BubbleShape.allCases)
    func drawsInsideBoundsWithWhiteText(shape: BubbleShape) throws {
        let s = Self.spec(shape)
        let out = Pixels(try #require(Renderer.makeImage(TestImage.document(TestImage.solid(width: 320, height: 200, .red), [Self.bubble(s)]))))
        let bounds = BubbleLayout.bounds(s), tb = BubbleLayout.textBox(s)
        let bg = out.rgba(0, 0)
        var outside = 0, blue = 0, white = 0
        for y in 0..<out.height {
            for x in 0..<out.width {
                let px = out.rgba(x, y)
                if px == bg { continue }
                if !bounds.contains(CGPoint(x: x, y: y)) { outside += 1; continue }
                if px == [RGBAColor.blue.r, RGBAColor.blue.g, RGBAColor.blue.b, 255] { blue += 1 }
                if px == [255, 255, 255, 255], tb.contains(CGPoint(x: x, y: y)) { white += 1 }
            }
        }
        #expect(outside == 0, "\(shape)")
        #expect(blue > 1000, "\(shape)")
        #expect(white > 50, "\(shape)")
    }

    @Test func whiteBubbleHasBlackText() {
        #expect(Self.spec(color: .white).textColor == .black)
        #expect(Self.spec().textColor == .white)
    }
}

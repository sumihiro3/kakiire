import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct ArrowOutlineTests {
    static let p0 = CGPoint(x: 20, y: 60), p1 = CGPoint(x: 280, y: 60)

    func arrow(width: Double = 20, color: RGBAColor = .red, head: ArrowHead = .tapered,
               dash: LineDash = .solid, outline: Bool) -> Annotation {
        Annotation(name: "a", content: .arrow(ArrowSpec(from: Self.p0, to: Self.p1, color: color, width: width,
                                                         head: head, dash: dash, outline: outline)))
    }

    @Test func defaultIsNoOutline() {
        #expect(ArrowSpec(from: .zero, to: .zero, color: .red, width: 1).outline == false)
    }

    @Test func outlineRoundTripsAndIsOmittedWhenOff() throws {
        let on = [arrow(outline: true)], off = [arrow(outline: false)]
        #expect(try JSONDecoder().decode([Annotation].self, from: JSONEncoder().encode(on)) == on)
        #expect(try JSONDecoder().decode([Annotation].self, from: JSONEncoder().encode(off)) == off)
        let offJSON = String(decoding: try JSONEncoder().encode(off), as: UTF8.self)
        #expect(!offJSON.contains("outline"))
        let onJSON = String(decoding: try JSONEncoder().encode(on), as: UTF8.self)
        #expect(onJSON.contains("\"outline\":true"))
    }

    @Test func missingKeyMeansNoOutline() throws {
        let json = ##"[{"type":"arrow","name":"a","geometry":{"from":[0,0],"to":[10,0]},"style":{"color":"#E82A2A","width":4}}]"##
        let back = try JSONDecoder().decode([Annotation].self, from: Data(json.utf8))
        guard case .arrow(let s) = back.first?.content else { Issue.record("not an arrow"); return }
        #expect(s.outline == false)
    }

    /// 背景の上で、`matches` に当たる画素の数。
    func count(_ a: Annotation, on bg: RGBAColor, _ matches: ([UInt8]) -> Bool) throws -> Int {
        let doc = TestImage.document(TestImage.solid(width: 300, height: 120, bg), [a])
        let px = Pixels(try #require(Renderer.makeImage(doc)))
        var n = 0
        for y in 0..<120 { for x in 0..<300 where matches(px.rgba(x, y)) { n += 1 } }
        return n
    }

    static func isWhite(_ p: [UInt8]) -> Bool { p[0] > 230 && p[1] > 230 && p[2] > 230 }
    static func isDark(_ p: [UInt8]) -> Bool { p[0] < 60 && p[1] < 60 && p[2] < 60 }

    @Test(arguments: [12.0, 32.0], [ArrowHead.tapered, .open])
    func outlineDrawsWhiteBandAroundArrow(width: Double, head: ArrowHead) throws {
        #expect(try count(arrow(width: width, head: head, outline: false), on: .black, Self.isWhite) == 0)
        #expect(try count(arrow(width: width, head: head, outline: true), on: .black, Self.isWhite) > 100)
        // 縁を付けても、矢印の芯は元の色のまま。
        let doc = TestImage.document(TestImage.solid(width: 300, height: 120, .black), [arrow(width: width, head: head, outline: true)])
        let px = Pixels(try #require(Renderer.makeImage(doc)))
        let core = px.rgba(150, 60)
        #expect(core[0] > 200 && core[1] < 80)
    }

    @Test func dashedArrowGetsOutlineToo() throws {
        #expect(try count(arrow(dash: .dashed, outline: false), on: .black, Self.isWhite) == 0)
        #expect(try count(arrow(dash: .dashed, outline: true), on: .black, Self.isWhite) > 100)
    }

    @Test func whiteArrowGetsDarkOutline() throws {
        #expect(try count(arrow(color: .white, outline: false), on: .blue, Self.isDark) == 0)
        #expect(try count(arrow(color: .white, outline: true), on: .blue, Self.isDark) > 100)
    }

    @Test func hitAreaGrowsByOutline() {
        let w = 20.0, tol: CGFloat = 2
        let p = CGPoint(x: 150, y: 60 + CGFloat(w) + tol + 1)
        #expect(!HitTesting.hits(arrow(width: w, outline: false), p, tol))
        #expect(HitTesting.hits(arrow(width: w, outline: true), p, tol))
    }

    @Test func boundsCoverOutline() throws {
        let a = arrow(width: 32, outline: true)
        let doc = TestImage.document(TestImage.solid(width: 300, height: 120, .black), [a])
        let px = Pixels(try #require(Renderer.makeImage(doc)))
        let b = a.bounds
        for y in 0..<120 {
            for x in 0..<300 where !b.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                #expect(Self.isDark(px.rgba(x, y)), "pixel outside bounds at \(x),\(y)")
                if !Self.isDark(px.rgba(x, y)) { return }
            }
        }
    }
}

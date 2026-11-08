import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct LineDashTests {
    static let p0 = CGPoint(x: 10, y: 20), p1 = CGPoint(x: 190, y: 20)

    func samples(_ dash: LineDash) -> [Annotation] {
        [
            Annotation(name: "a", content: .arrow(ArrowSpec(from: Self.p0, to: Self.p1, color: .red, width: 12, dash: dash))),
            Annotation(name: "l", content: .line(LineSpec(from: Self.p0, to: Self.p1, color: .red, width: 4, dash: dash))),
            Annotation(name: "r", content: .rect(ShapeSpec(rect: CGRect(x: 1, y: 2, width: 30, height: 40), color: .red, width: 4, dash: dash))),
            Annotation(name: "e", content: .ellipse(ShapeSpec(rect: CGRect(x: 1, y: 2, width: 30, height: 40), color: .red, width: 4, dash: dash))),
            Annotation(name: "p", content: .pen(StrokeSpec(points: [Self.p0, Self.p1], color: .red, width: 4, dash: dash))),
        ]
    }

    @Test(arguments: LineDash.allCases)
    func roundTrips(dash: LineDash) throws {
        let anns = samples(dash)
        let back = try JSONDecoder().decode([Annotation].self, from: JSONEncoder().encode(anns))
        #expect(back == anns)
    }

    @Test func solidIsNotWrittenAndMissingMeansSolid() throws {
        let json = String(decoding: try JSONEncoder().encode(samples(.solid)), as: UTF8.self)
        #expect(!json.contains("dash"))
        let dashed = String(decoding: try JSONEncoder().encode(samples(.dashed)), as: UTF8.self)
        #expect(dashed.contains("\"dash\":\"dashed\""))
    }

    /// 横線上(y = 20)の画素のうち、線の色でない画素の数。
    func gaps(_ a: Annotation) throws -> Int {
        let doc = TestImage.document(TestImage.solid(width: 200, height: 40, .white), [a])
        let px = Pixels(try #require(Renderer.makeImage(doc)))
        return (20..<180).filter { px.rgba($0, 20)[1] > 200 }.count
    }

    @Test(arguments: [LineDash.dashed, .dotted, .dashDot])
    func dashedLineHasGaps(dash: LineDash) throws {
        #expect(try gaps(samples(.solid)[1]) == 0)
        #expect(try gaps(samples(dash)[1]) > 10)
    }

    @Test func dashedPenAndArrowHaveGaps() throws {
        #expect(try gaps(samples(.dashed)[4]) > 10)
        #expect(try gaps(samples(.solid)[0]) == 0)
        #expect(try gaps(samples(.dashed)[0]) > 10)
    }
}

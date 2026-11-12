import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct AlignmentTests {
    let base = TestImage.document(TestImage.solid(width: 400, height: 300, .white))

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, width: Double = 4) -> Annotation {
        Annotation(name: "矩形", content: .rect(ShapeSpec(rect: CGRect(x: x, y: y, width: w, height: h), color: .pink, width: width)))
    }

    func frames(_ d: Document) -> [CGRect] { d.annotations.map(\.frame) }

    func aligned(_ items: [Annotation], _ a: Alignment) -> Document {
        let d = base.applying(items.map { .add($0) })
        return d.applying(Arrange.align(Set(items.map(\.id)), a, in: d))
    }

    @Test func alignLeftRightCenterX() {
        let items = [rect(10, 20, 40, 30), rect(100, 80, 60, 10)]
        #expect(frames(aligned(items, .left)).map(\.minX) == [10, 10])
        #expect(frames(aligned(items, .right)).map(\.maxX) == [160, 160])
        #expect(frames(aligned(items, .centerX)).map(\.midX) == [85, 85])
        // 横に揃えても縦は動かない。
        #expect(frames(aligned(items, .left)).map(\.minY) == [20, 80])
    }

    @Test func alignTopIsMinYBecauseYPointsDown() {
        let items = [rect(10, 20, 40, 30), rect(100, 80, 60, 10)]
        #expect(frames(aligned(items, .top)).map(\.minY) == [20, 20])
        #expect(frames(aligned(items, .bottom)).map(\.maxY) == [90, 90])
        #expect(frames(aligned(items, .centerY)).map(\.midY) == [55, 55])
        #expect(frames(aligned(items, .top)).map(\.minX) == [10, 100])
    }

    @Test func frameIgnoresStrokeAndArrowheadPadding() {
        let arrow = Annotation(name: "矢印", content: .arrow(ArrowSpec(from: CGPoint(x: 200, y: 50), to: CGPoint(x: 300, y: 60), color: .pink, width: 8)))
        #expect(arrow.frame == CGRect(x: 200, y: 50, width: 100, height: 10))
        let thick = rect(50, 100, 20, 20, width: 20)
        let d = aligned([arrow, thick], .left)
        #expect(frames(d).map(\.minX) == [50, 50])
    }

    @Test func lockedStaysAndActsAsAnchor() {
        var anchor = rect(200, 20, 40, 30); anchor.locked = true
        let free = rect(10, 80, 40, 30)
        let d = aligned([anchor, free], .left)
        // 範囲の左端は free の 10。ロックした方は動かない。
        #expect(frames(d) == [CGRect(x: 200, y: 20, width: 40, height: 30), CGRect(x: 10, y: 80, width: 40, height: 30)])
        let r = aligned([anchor, free], .right)
        #expect(frames(r).map(\.maxX) == [240, 240])
    }

    @Test func hiddenAndSingleAreIgnored() {
        var hidden = rect(200, 20, 40, 30); hidden.hidden = true
        let a = rect(10, 80, 40, 30)
        let d = base.applying([.add(hidden), .add(a)])
        #expect(Arrange.align([hidden.id, a.id], .left, in: d).isEmpty)
        #expect(Arrange.align([a.id], .left, in: d).isEmpty)
    }

    @Test func alreadyAlignedProducesNoOps() {
        let items = [rect(10, 20, 40, 30), rect(10, 80, 60, 10)]
        let d = base.applying(items.map { .add($0) })
        #expect(Arrange.align(Set(items.map(\.id)), .left, in: d).isEmpty)
    }

    @Test func alignMovesEachByExactVector() {
        let a = rect(10, 20, 40, 30), b = rect(100, 80, 60, 10)
        let d = base.applying([.add(a), .add(b)])
        #expect(Arrange.align([a.id, b.id], .left, in: d) == [.move([b.id], by: CGVector(dx: -90, dy: 0))])
    }

    @Test func distributeHorizontallyEqualizesGapsBetweenEdges() {
        // 配列の順と位置の順を変えておく。
        let items = [rect(300, 0, 50, 10), rect(0, 50, 20, 10), rect(40, 100, 30, 10), rect(200, 150, 10, 10)]
        var d = base.applying(items.map { .add($0) })
        d = d.applying(Arrange.distribute(Set(items.map(\.id)), .horizontal, in: d))
        let sorted = frames(d).sorted { $0.minX < $1.minX }
        #expect(sorted.first!.minX == 0)
        #expect(sorted.last!.maxX == 350)
        let gaps = zip(sorted, sorted.dropFirst()).map { $1.minX - $0.maxX }
        #expect(gaps.allSatisfy { abs($0 - gaps[0]) < 1e-9 })
        #expect(abs(gaps[0] - (350 - 110) / 3) < 1e-9)
        #expect(frames(d).map(\.minY) == [0, 50, 100, 150])
    }

    @Test func distributeVertically() {
        let items = [rect(0, 0, 10, 10), rect(50, 30, 10, 40), rect(100, 190, 10, 10)]
        var d = base.applying(items.map { .add($0) })
        d = d.applying(Arrange.distribute(Set(items.map(\.id)), .vertical, in: d))
        #expect(frames(d).map(\.minY) == [0, 80, 190])
    }

    @Test func distributeNeedsThree() {
        let items = [rect(0, 0, 10, 10), rect(100, 50, 10, 10)]
        let d = base.applying(items.map { .add($0) })
        #expect(Arrange.distribute(Set(items.map(\.id)), .horizontal, in: d).isEmpty)
    }
}

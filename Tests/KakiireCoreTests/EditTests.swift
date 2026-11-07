import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct EditTests {
    let base = TestImage.document(TestImage.solid(width: 200, height: 100, .white))

    func arrow(_ from: CGPoint = .init(x: 10, y: 10), _ to: CGPoint = .init(x: 100, y: 50)) -> Annotation {
        Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: from, to: to, color: .pink, width: 8)))
    }

    func rect(_ r: CGRect = .init(x: 20, y: 20, width: 60, height: 40)) -> Annotation {
        Annotation(name: "矩形 1", content: .rect(ShapeSpec(rect: r, color: .pink, width: 4)))
    }

    @Test func addAppendsOnTopAndInsertsAtIndex() {
        let a = arrow(), r = rect()
        let d = base.applying([.add(a), .add(r, index: 0)])
        #expect(d.annotations.map(\.id) == [r.id, a.id])
    }

    @Test func removeAndReorder() {
        let a = arrow(), r = rect(), r2 = rect()
        var d = base.applying([.add(a), .add(r), .add(r2)])
        d = d.applying(.reorder(r2.id, to: 0))
        #expect(d.annotations.map(\.id) == [r2.id, a.id, r.id])
        d = d.applying(.remove([a.id]))
        #expect(d.annotations.map(\.id) == [r2.id, r.id])
    }

    @Test func moveSkipsLocked() {
        var r = rect(); r.locked = true
        let a = arrow()
        let d = base.applying([.add(a), .add(r), .move([a.id, r.id], by: CGVector(dx: 5, dy: 7))])
        guard case .arrow(let s) = d.annotations[0].content else { Issue.record(); return }
        #expect(s.from == CGPoint(x: 15, y: 17))
        #expect(d.annotations[1] == r)
    }

    @Test func layerFlags() {
        let a = arrow()
        let d = base.applying([.add(a), .setHidden([a.id], true), .setLocked([a.id], true), .rename(a.id, "目印")])
        #expect(d.annotations[0].hidden && d.annotations[0].locked)
        #expect(d.annotations[0].name == "目印")
    }

    @Test func replaceBaseKeepsAnnotationsAndClearsCrop() {
        var d = base.applying(.add(arrow()))
        d.canvas.crop = CGRect(x: 0, y: 0, width: 10, height: 10)
        let other = TestImage.asset(TestImage.solid(width: 30, height: 30, .black))
        d = d.applying(.replaceBase(other))
        #expect(d.base.asset == other)
        #expect(d.canvas.crop == nil)
        #expect(d.annotations.count == 1)
    }

    @Test func sessionCollapsesDragIntoOneChange() {
        let a = arrow()
        let start = base.applying(.add(a))
        var s = EditSession(start)
        for i in 1...100 { s.update(.move([a.id], by: CGVector(dx: CGFloat(i), dy: 0))) }
        let result = s.commit()
        #expect(result?.before == start)
        guard case .arrow(let spec) = result?.after.annotations[0].content else { Issue.record(); return }
        // 累計を渡すので、100 回の update でも移動量は最後の値だけになる。
        #expect(spec.from.x == 110)
    }

    @Test func sessionWithoutChangeCommitsNothing() {
        var s = EditSession(base)
        s.update([])
        #expect(s.commit() == nil)
    }

    @Test func hitTestPicksFrontmostAndSkipsHiddenLocked() {
        let back = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
        var front = Annotation(name: "o", content: .obscure(ObscureSpec(rect: CGRect(x: 0, y: 0, width: 100, height: 100), mode: .pixelate, strength: 10)))
        let d = base.applying([.add(back), .add(front)])
        #expect(HitTesting.annotation(at: CGPoint(x: 50, y: 50), in: d, tolerance: 2) == front.id)

        front.hidden = true
        let d2 = d.applying(.replace(front))
        // 枠線だけの矩形は内側では当たらず、枠の上で当たる。
        #expect(HitTesting.annotation(at: CGPoint(x: 50, y: 50), in: d2, tolerance: 2) == nil)
        #expect(HitTesting.annotation(at: CGPoint(x: 1, y: 50), in: d2, tolerance: 2) == back.id)
    }

    @Test func hitTestArrowNearSegment() {
        let a = arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        let d = base.applying(.add(a))
        #expect(HitTesting.annotation(at: CGPoint(x: 50, y: 6), in: d, tolerance: 2) == a.id)
        #expect(HitTesting.annotation(at: CGPoint(x: 50, y: 30), in: d, tolerance: 2) == nil)
    }

    @Test func handlesAndResize() {
        let r = rect(CGRect(x: 10, y: 10, width: 50, height: 30))
        #expect(HitTesting.handle(at: CGPoint(x: 61, y: 41), of: r, tolerance: 3) == .bottomRight)
        let bigger = r.resized(.bottomRight, to: CGPoint(x: 110, y: 60))
        guard case .rect(let s) = bigger.content else { Issue.record(); return }
        #expect(s.rect == CGRect(x: 10, y: 10, width: 100, height: 50))

        // 反対側まで引っ張ると正規化される。
        let flipped = r.resized(.left, to: CGPoint(x: 100, y: 0))
        guard case .rect(let f) = flipped.content else { Issue.record(); return }
        #expect(f.rect == CGRect(x: 60, y: 10, width: 40, height: 30))

        let square = r.resized(.bottomRight, to: CGPoint(x: 110, y: 30), constrain: true)
        guard case .rect(let q) = square.content else { Issue.record(); return }
        #expect(q.rect.width == q.rect.height)
    }

    @Test func arrowEndpointSnap() {
        let a = arrow(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10))
        let snapped = a.resized(.end, to: CGPoint(x: 100, y: 8), constrain: true)
        guard case .arrow(let s) = snapped.content else { Issue.record(); return }
        #expect(abs(s.to.y) < 0.001)
    }

    @Test func marqueeSelection() {
        let a = arrow(CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20))
        let r = rect(CGRect(x: 150, y: 50, width: 20, height: 20))
        let d = base.applying([.add(a), .add(r)])
        #expect(HitTesting.annotations(intersecting: CGRect(x: 0, y: 0, width: 50, height: 50), in: d) == [a.id])
    }
}

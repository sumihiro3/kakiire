import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct AnnotationCopyTests {
    let base = TestImage.document(TestImage.solid(width: 400, height: 300, .white))
    let label: (AnnotationContent) -> String = { $0.typeName }

    func rect(_ r: CGRect = .init(x: 20, y: 20, width: 60, height: 40), name: String = "rect 1") -> Annotation {
        Annotation(name: name, content: .rect(ShapeSpec(rect: r, color: .pink, width: 4)))
    }

    func rectOf(_ a: Annotation?) -> CGRect? {
        if case .rect(let s) = a?.content { s.rect } else { nil }
    }

    @Test func duplicateShiftsByStepWithNewIdAndName() {
        let r = rect()
        let doc = base.applying(.add(r))
        let (ops, ids) = AnnotationCopy.paste([r], into: doc, step: 10, label: label)
        let d = doc.applying(ops)
        #expect(ids.count == 1 && ids[0] != r.id)
        let dup = d.annotation(ids[0])
        #expect(rectOf(dup) == CGRect(x: 30, y: 30, width: 60, height: 40))
        #expect(dup?.name == "rect 2")
    }

    @Test func repeatedPasteKeepsShifting() {
        let r = rect()
        var doc = base.applying(.add(r))
        for n in 1...3 {
            let (ops, ids) = AnnotationCopy.paste([r], into: doc, step: 10, label: label)
            doc = doc.applying(ops)
            #expect(rectOf(doc.annotation(ids[0]))?.origin == CGPoint(x: 20 + 10 * n, y: 20 + 10 * n))
        }
        #expect(doc.annotations.map(\.name) == ["rect 1", "rect 2", "rect 3", "rect 4"])
    }

    @Test func pasteIntoOtherDocumentKeepsPosition() {
        let r = rect()
        let (ops, ids) = AnnotationCopy.paste([r], into: base, step: 10, label: label)
        #expect(rectOf(base.applying(ops).annotation(ids[0])) == r.content.rectValue)
    }

    @Test func pasteOutsideVisibleAreaMovesToItsCenter() {
        let r = rect(CGRect(x: 1000, y: 1000, width: 60, height: 40))
        let visible = CGRect(x: 0, y: 0, width: 400, height: 300)
        let (ops, ids) = AnnotationCopy.paste([r], into: base, step: 10, visible: visible, label: label)
        let b = base.applying(ops).annotation(ids[0])!.bounds
        #expect(abs(b.midX - 200) <= 1 && abs(b.midY - 150) <= 1)
    }

    @Test func pasteAtPointCentersTheGroupAndKeepsRelativeLayout() {
        let a = rect(CGRect(x: 0, y: 0, width: 20, height: 20)), b = rect(CGRect(x: 80, y: 40, width: 20, height: 20))
        let (ops, ids) = AnnotationCopy.paste([a, b], into: base, step: 10, center: CGPoint(x: 200, y: 200), label: label)
        let d = base.applying(ops)
        let ra = rectOf(d.annotation(ids[0]))!, rb = rectOf(d.annotation(ids[1]))!
        #expect(rb.origin.x - ra.origin.x == 80 && rb.origin.y - ra.origin.y == 40)
        let mid = ra.union(rb)
        #expect(abs(mid.midX - 200) <= 1 && abs(mid.midY - 200) <= 1)
        #expect(d.annotations.map(\.name) == ["rect 1", "rect 2"])
    }

    @Test func pastedItemsAreVisibleAndUnlocked() {
        var r = rect()
        r.hidden = true; r.locked = true
        let (ops, ids) = AnnotationCopy.paste([r], into: base, step: 10, label: label)
        let p = base.applying(ops).annotation(ids[0])!
        #expect(!p.hidden && !p.locked)
    }

    /// 複製・ペーストしたスタンプは番号を進めず、元と同じ番号のまま(2026-11-13 に決定)。
    @Test func duplicatedStampKeepsItsNumber() {
        let s = Annotation(name: "stamp 1", content: .stamp(StampSpec(center: CGPoint(x: 50, y: 50), number: 3, color: .pink, diameter: 40)))
        let doc = base.applying(.add(s))
        let (ops, ids) = AnnotationCopy.paste([s], into: doc, step: 10, label: label)
        guard case .stamp(let dup) = doc.applying(ops).annotation(ids[0])?.content else { Issue.record("not stamp"); return }
        #expect(dup.number == 3)
        #expect(dup.center == CGPoint(x: 60, y: 60))
    }

    @Test func copyableKeepsStackOrderAndSkipsUnknown() {
        let a = rect(name: "a"), b = rect(name: "b")
        let u = Annotation(name: "u", content: .unknown(type: "future", raw: .object([:])))
        let doc = base.applying([.add(a), .add(u), .add(b)])
        #expect(AnnotationCopy.copyable([b.id, u.id, a.id], in: doc).map(\.id) == [a.id, b.id])
    }
}

private extension AnnotationContent {
    var rectValue: CGRect? { if case .rect(let s) = self { s.rect } else { nil } }
}

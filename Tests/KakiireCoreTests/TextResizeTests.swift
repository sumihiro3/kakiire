import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

/// テキストは四隅のつまみで外形を変えると、その外形に収まるよう文字サイズが変わる。
@Suite struct TextResizeTests {
    let spec = TextSpec(origin: CGPoint(x: 100, y: 50), text: "Hello\nKakiire", color: .red, fontSize: 30)
    var annotation: Annotation { Annotation(name: "t", content: .text(spec)) }

    func text(_ a: Annotation) -> TextSpec {
        guard case .text(let t) = a.content else { Issue.record(); return spec }
        return t
    }

    @Test func textHasFourCornerHandles() {
        #expect(annotation.handles.map(\.0) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
        let b = TextLayout.bounds(spec)
        #expect(annotation.handles.first { $0.0 == .bottomRight }?.1 == CGPoint(x: b.maxX, y: b.maxY))
    }

    @Test func draggingBottomRightScalesFontAndKeepsTopLeft() {
        let b = TextLayout.bounds(spec)
        let r = annotation.resized(.bottomRight, to: CGPoint(x: b.minX + b.width * 2, y: b.minY + b.height * 2))
        let t = text(r)
        #expect(abs(t.fontSize - 60) < 3)
        #expect(t.origin == spec.origin)
    }

    @Test func draggingTopLeftKeepsBottomRight() {
        let b = TextLayout.bounds(spec)
        let r = annotation.resized(.topLeft, to: CGPoint(x: b.maxX - b.width / 2, y: b.maxY - b.height / 2))
        let nb = TextLayout.bounds(text(r))
        #expect(abs(text(r).fontSize - 15) < 2)
        #expect(abs(nb.maxX - b.maxX) < 0.001 && abs(nb.maxY - b.maxY) < 0.001)
    }

    /// 縦横比が違う外形にしたときは、はみ出さないよう小さいほうの倍率を使う。
    @Test func usesSmallerRatioToFit() {
        let b = TextLayout.bounds(spec)
        let r = annotation.resized(.bottomRight, to: CGPoint(x: b.minX + b.width * 3, y: b.minY + b.height * 1.5))
        #expect(abs(text(r).fontSize - 45) < 3)
    }

    @Test func fontSizeIsClamped() {
        let r = annotation.resized(.bottomRight, to: spec.origin)
        #expect(text(r).fontSize == 4)
    }
}

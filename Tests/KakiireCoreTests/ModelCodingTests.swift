import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

@Suite struct ModelCodingTests {
    func loadFixture() throws -> DocumentDescriptor {
        let data = try Data(contentsOf: fixtureURL("document-v1.json"))
        return try JSONDecoder().decode(DocumentDescriptor.self, from: data)
    }

    @Test func decodesHandoffSkeleton() throws {
        let d = try loadFixture()
        #expect(d.canvas.crop == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(d.canvas.outputScale == 0.5)
        #expect(d.base.asset == "base.png")
        #expect(d.annotations.count == 4)

        guard case .arrow(let arrow) = d.annotations[0].content else { Issue.record("not arrow"); return }
        #expect(arrow.from == CGPoint(x: 120, y: 80))
        #expect(arrow.to == CGPoint(x: 400, y: 260))
        #expect(arrow.color == RGBAColor(0xE5, 0x30, 0x6B))
        #expect(arrow.width == 8)
        #expect(arrow.head == .tapered)

        guard case .obscure(let ob) = d.annotations[1].content else { Issue.record("not obscure"); return }
        #expect(ob.rect == CGRect(x: 600, y: 40, width: 300, height: 60))
        #expect(ob.mode == .pixelate)
        #expect(d.annotations[1].hidden == false)

        guard case .text(let t) = d.annotations[2].content else { Issue.record("not text"); return }
        #expect(t.text == "ここを押す")
        #expect(t.fontSize == 36)
    }

    @Test func unknownTypeSurvivesRoundTrip() throws {
        var d = try loadFixture()
        guard case .unknown(let type, _) = d.annotations[3].content else { Issue.record("not unknown"); return }
        #expect(type == "sticker")
        #expect(d.annotations[3].locked == true)

        // レイヤー操作で名前を変えても、知らない中身は消えない。
        d.annotations[3].name = "改名"
        let data = try JSONEncoder().encode(d)
        let obj = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let root) = obj, case .array(let anns) = root["annotations"],
              case .object(let stamp) = anns[3] else { Issue.record("bad shape"); return }
        #expect(stamp["type"] == .string("sticker"))
        #expect(stamp["name"] == .string("改名"))
        #expect(stamp["geometry"] == .object(["center": .array([.number(10), .number(20)])]))
        #expect(stamp["style"] == .object([
            "number": .number(3),
            "future": .object(["nested": .array([.number(1), .string("a"), .null])]),
        ]))
    }

    @Test func roundTripIsStable() throws {
        let d = try loadFixture()
        let once = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(DocumentDescriptor.self, from: once)
        #expect(back == d)
    }

    @Test func allKnownTypesRoundTrip() throws {
        let anns: [Annotation] = [
            Annotation(name: "a", content: .arrow(ArrowSpec(from: .init(x: 1, y: 2), to: .init(x: 3, y: 4), color: .blue, width: 5, head: .open))),
            Annotation(name: "l", hidden: true, content: .line(LineSpec(from: .zero, to: .init(x: 9, y: 9), color: .black, width: 2))),
            Annotation(name: "r", content: .rect(ShapeSpec(rect: .init(x: 1, y: 1, width: 5, height: 6), color: .red, width: 3, fill: RGBAColor(1, 2, 3, 128)))),
            Annotation(name: "e", locked: true, content: .ellipse(ShapeSpec(rect: .init(x: 0, y: 0, width: 2, height: 2), color: .green, width: 1))),
            Annotation(name: "t", content: .text(TextSpec(origin: .init(x: 5, y: 5), text: "a\nb", color: .white, fontSize: 20, bold: false, outline: false))),
            Annotation(name: "o", content: .obscure(ObscureSpec(rect: .init(x: 3, y: 3, width: 10, height: 10), mode: .blur, strength: 7))),
            Annotation(name: "b", content: .bubble(BubbleSpec(origin: .init(x: 4, y: 4), text: "!", color: .pink, fontSize: 18, shape: .shout, tail: .init(x: 0, y: 40)))),
        ]
        let d = DocumentDescriptor(canvas: Canvas(), base: .init(asset: "base.png"), annotations: anns)
        let back = try JSONDecoder().decode(DocumentDescriptor.self, from: JSONEncoder().encode(d))
        #expect(back == d)
    }

    @Test func colorHex() {
        #expect(RGBAColor(hex: "#E5306B") == RGBAColor(0xE5, 0x30, 0x6B))
        #expect(RGBAColor(hex: "#11223344") == RGBAColor(0x11, 0x22, 0x33, 0x44))
        #expect(RGBAColor(0x11, 0x22, 0x33, 0x44).hex == "#11223344")
        #expect(RGBAColor.pink.hex == "#E5306B")
        #expect(RGBAColor(hex: "zz") == nil)
    }

    @Test func nextNameCountsSameKind() {
        let doc = TestImage.document(TestImage.solid(width: 4, height: 4, .white), [
            Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: .zero, to: .zero, color: .pink, width: 1))),
        ])
        // 表示名は App が言語に合わせて渡す。数えるのは種類で、名前の文字列ではない。
        #expect(doc.nextName(for: .arrow(ArrowSpec(from: .zero, to: .zero, color: .pink, width: 1)), label: "Arrow") == "Arrow 2")
        #expect(doc.nextName(for: .line(LineSpec(from: .zero, to: .zero, color: .pink, width: 1)), label: "線") == "線 1")
        let pixelate = AnnotationContent.obscure(ObscureSpec(rect: .zero, mode: .pixelate, strength: 1))
        let blur = AnnotationContent.obscure(ObscureSpec(rect: .zero, mode: .blur, strength: 1))
        let withMosaic = TestImage.document(TestImage.solid(width: 4, height: 4, .white), [Annotation(name: "m", content: pixelate)])
        #expect(withMosaic.nextName(for: blur, label: "Blur") == "Blur 1")
        #expect(withMosaic.nextName(for: pixelate, label: "Pixelate") == "Pixelate 2")
    }
}

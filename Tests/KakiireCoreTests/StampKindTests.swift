import CoreGraphics
import Foundation
import Testing
@testable import KakiireCore

/// スタンプの種類(数字・英字・記号・絵文字)。
@Suite struct StampKindTests {
    func stamp(_ kind: StampKind, _ n: Int = 1) -> Annotation {
        Annotation(name: "s", content: .stamp(StampSpec(center: CGPoint(x: 40, y: 30), number: n, color: .red, diameter: 32, kind: kind)))
    }

    @Test func defaultIsNumber() {
        #expect(StampSpec(center: .zero, number: 1, color: .red, diameter: 10).kind == .number)
    }

    @Test func labels() {
        func label(_ k: StampKind, _ n: Int) -> String { StampSpec(center: .zero, number: n, color: .red, diameter: 10, kind: k).label }
        #expect(label(.number, 12) == "12")
        #expect(label(.letter, 1) == "A")
        #expect(label(.letter, 26) == "Z")
        #expect(label(.letter, 27) == "AA")
        #expect(label(.letter, 28) == "AB")
        #expect(label(.letter, 52) == "AZ")
        #expect(label(.letter, 53) == "BA")
        #expect(label(.symbol("✓"), 5) == "✓")
        #expect(label(.emoji("👍"), 5) == "👍")
    }

    @Test func numbersAndLettersCountSeparately() {
        let doc = TestImage.document(TestImage.solid(width: 80, height: 60, .white),
                                     [stamp(.number, 2), stamp(.letter, 1), stamp(.letter, 2), stamp(.symbol("✓"), 9)])
        #expect(doc.nextStampNumber(for: .number) == 3)
        #expect(doc.nextStampNumber(for: .letter) == 3)
        #expect(doc.nextStampNumber(for: .symbol("!")) == 1)
        #expect(doc.nextStampNumber(for: .emoji("👍")) == 1)
    }

    @Test func roundTrips() throws {
        let all = [stamp(.number, 4), stamp(.letter, 3), stamp(.symbol("✗")), stamp(.emoji("⚠️"))]
        #expect(try JSONDecoder().decode([Annotation].self, from: JSONEncoder().encode(all)) == all)
        // 数字はこれまでと同じ形(kind を書かない)。
        let numberJSON = String(decoding: try JSONEncoder().encode([stamp(.number, 4)]), as: UTF8.self)
        #expect(!numberJSON.contains("kind"))
    }

    @Test func oldFormatReadsAsNumber() throws {
        let json = ##"[{"type":"stamp","name":"s","number":7,"geometry":{"center":[1,2]},"style":{"color":"#E82A2A","diameter":30}}]"##
        let back = try JSONDecoder().decode([Annotation].self, from: Data(json.utf8))
        guard case .stamp(let s) = back.first?.content else { Issue.record("not a stamp"); return }
        #expect(s.kind == .number && s.number == 7)
    }

    @Test func unknownKindFallsBackToNumber() throws {
        let json = ##"[{"type":"stamp","name":"s","number":7,"geometry":{"center":[1,2]},"style":{"color":"#E82A2A","diameter":30,"kind":"hexagon"}}]"##
        let back = try JSONDecoder().decode([Annotation].self, from: Data(json.utf8))
        guard case .stamp(let s) = back.first?.content else { Issue.record("not a stamp"); return }
        #expect(s.kind == .number)
    }

    @Test func emojiHasNoColoredDisc() throws {
        // 絵文字は色の丸を描かない。数字は赤い丸になる。
        let white = TestImage.solid(width: 80, height: 60, .white)
        func reds(_ a: Annotation) throws -> Int {
            let px = Pixels(try #require(Renderer.makeImage(TestImage.document(white, [a]))))
            var n = 0
            for y in 0..<px.height { for x in 0..<px.width {
                let p = px.rgba(x, y)
                if p[0] > 200 && p[1] < 80 && p[2] < 80 { n += 1 }
            } }
            return n
        }
        #expect(try reds(stamp(.number, 1)) > 300)
        #expect(try reds(stamp(.emoji("💡"))) < 20)
    }
}

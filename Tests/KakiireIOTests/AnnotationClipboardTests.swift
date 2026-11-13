import CoreGraphics
import Foundation
import Testing
import KakiireCore
@testable import KakiireIO

@Suite struct AnnotationClipboardTests {
    @Test func roundTripIncludesOverlayImages() throws {
        let asset = try ImageImport.asset(from: ImageIOTests.noise(40, 30))
        let items = [
            Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: .zero, to: CGPoint(x: 50, y: 20), color: .pink, width: 8))),
            Annotation(name: "画像 1", content: .image(ImageSpec(asset: asset, rect: CGRect(x: 5, y: 5, width: 40, height: 30), shadow: 4))),
        ]
        let back = try AnnotationClipboard.decode(AnnotationClipboard.encode(items))
        #expect(back == items)
        guard case .image(let im) = back[1].content else { Issue.record("not image"); return }
        #expect(im.asset.data == asset.data)
    }

    @Test func newerFormatIsRejected() throws {
        let data = Data(#"{"format": 99, "annotations": [], "assets": {}}"#.utf8)
        #expect(throws: AnnotationClipboardError.self) { try AnnotationClipboard.decode(data) }
    }
}

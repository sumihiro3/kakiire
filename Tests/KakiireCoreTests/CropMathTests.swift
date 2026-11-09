import CoreGraphics
import Testing
@testable import KakiireCore

/// 切り抜きの範囲を px で入力したときの整え方。
@Suite struct CropMathTests {
    let image = CGSize(width: 1000, height: 800)

    @Test func roundsToWholePixels() {
        let r = CropMath.fit(CGRect(x: 10.4, y: 20.6, width: 300.5, height: 199.4), in: image)
        #expect(r == CGRect(x: 10, y: 21, width: 301, height: 199))
    }

    @Test func shiftsInsideKeepingSize() {
        let r = CropMath.fit(CGRect(x: 900, y: 700, width: 300, height: 200), in: image)
        #expect(r == CGRect(x: 700, y: 600, width: 300, height: 200))
        let l = CropMath.fit(CGRect(x: -50, y: -10, width: 300, height: 200), in: image)
        #expect(l == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func stopsAtImageSize() {
        let r = CropMath.fit(CGRect(x: 100, y: 100, width: 5000, height: 900), in: image)
        #expect(r == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func atLeastOnePixel() {
        let r = CropMath.fit(CGRect(x: 10, y: 10, width: 0, height: 0.2), in: image)
        #expect(r.width == 1 && r.height == 1)
    }

    @Test func aspectLockedHeightFollowsWidth() {
        #expect(CropMath.height(forWidth: 400, keeping: CGSize(width: 800, height: 600)) == 300)
        #expect(CropMath.width(forHeight: 300, keeping: CGSize(width: 800, height: 600)) == 400)
    }
}

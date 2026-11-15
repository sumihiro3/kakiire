import CoreGraphics
import Foundation

/// 画像全体にかける向きの変更。元画像は書き換えず、`BaseImage` の向きと注釈の座標を変える。
public enum ImageTransform: Sendable, Equatable {
    case rotateClockwise, rotateCounterclockwise, flipHorizontal, flipVertical

    /// 中心を原点、y 下向きとした 2×2 の整数行列 (a, b, c, d):x' = a·x + c·y、y' = b·x + d·y。
    var matrix: Matrix2 {
        switch self {
        case .rotateClockwise: Matrix2(a: 0, b: 1, c: -1, d: 0)
        case .rotateCounterclockwise: Matrix2(a: 0, b: -1, c: 1, d: 0)
        case .flipHorizontal: Matrix2(a: -1, b: 0, c: 0, d: 1)
        case .flipVertical: Matrix2(a: 1, b: 0, c: 0, d: -1)
        }
    }

    var swapsAxes: Bool { self == .rotateClockwise || self == .rotateCounterclockwise }

    /// 変換前の画像サイズ `size` の座標を、変換後の座標に移す。
    func apply(_ p: CGPoint, in size: CGSize) -> CGPoint {
        switch self {
        case .rotateClockwise: CGPoint(x: size.height - p.y, y: p.x)
        case .rotateCounterclockwise: CGPoint(x: p.y, y: size.width - p.x)
        case .flipHorizontal: CGPoint(x: size.width - p.x, y: p.y)
        case .flipVertical: CGPoint(x: p.x, y: size.height - p.y)
        }
    }

    func apply(_ r: CGRect, in size: CGSize) -> CGRect {
        let r = r.standardized
        return CGRect(corner: apply(CGPoint(x: r.minX, y: r.minY), in: size), apply(CGPoint(x: r.maxX, y: r.maxY), in: size))
    }
}

/// 二面体群 D4 の元を表す整数行列。
struct Matrix2: Equatable {
    var a, b, c, d: Int

    static let identity = Matrix2(a: 1, b: 0, c: 0, d: 1)

    /// self を先に、`then` を後にかけた合成(then · self)。
    func then(_ m: Matrix2) -> Matrix2 {
        Matrix2(a: m.a * a + m.c * b, b: m.b * a + m.d * b, c: m.a * c + m.c * d, d: m.b * c + m.d * d)
    }
}

extension BaseImage {
    /// 「回転してから反転」(Renderer.transformed と同じ順)を行列にしたもの。
    var orientationMatrix: Matrix2 {
        var m = Matrix2.identity
        let quarter = rotation.rawValue / 90
        for _ in 0..<quarter { m = m.then(ImageTransform.rotateClockwise.matrix) }
        if flipV { m = m.then(ImageTransform.flipVertical.matrix) }
        if flipH { m = m.then(ImageTransform.flipHorizontal.matrix) }
        return m
    }

    /// 今の向きに `t` を重ねた向き。反転と回転は可換でないので、行列で合成してから分解し直す。
    func transformed(by t: ImageTransform) -> BaseImage {
        let target = orientationMatrix.then(t.matrix)
        // 上下反転は「左右反転 + 180°」で表せるので、flipV は使わずに8通りを網羅できる。
        for r in Rotation.allCases {
            for h in [false, true] {
                let candidate = BaseImage(asset: asset, rotation: r, flipH: h, flipV: false)
                if candidate.orientationMatrix == target { return candidate }
            }
        }
        return self
    }
}

public extension Annotation {
    /// 画像の向きの変更に合わせて移したコピー。`size` は変換前の画像サイズ。
    /// 画像オーバーレイは中身ごと回す。テキスト・スタンプ・吹き出しの本体は読めるよう、外形の中心だけを移して正立のままにする。
    func transformed(by t: ImageTransform, in size: CGSize) -> Annotation {
        func pt(_ p: CGPoint) -> CGPoint { t.apply(p, in: size) }
        func rect(_ r: CGRect) -> CGRect { t.apply(r, in: size) }
        func recentered(_ r: CGRect) -> CGVector { pt(r.center) - r.center }

        switch content {
        case .arrow(var a): a.from = pt(a.from); a.to = pt(a.to); return with(content: .arrow(a))
        case .line(var l): l.from = pt(l.from); l.to = pt(l.to); return with(content: .line(l))
        case .rect(var s): s.rect = rect(s.rect); return with(content: .rect(s))
        case .ellipse(var s): s.rect = rect(s.rect); return with(content: .ellipse(s))
        case .obscure(var o): o.rect = rect(o.rect); return with(content: .obscure(o))
        case .highlighter(var p): p.points = p.points.map(pt); return with(content: .highlighter(p))
        case .pen(var p): p.points = p.points.map(pt); return with(content: .pen(p))
        case .stamp(var st): st.center = pt(st.center); return with(content: .stamp(st))
        case .text(var tx):
            tx.origin = tx.origin + recentered(TextLayout.bounds(tx)); return with(content: .text(tx))
        case .bubble(var b):
            // 本体は正立のまま中心だけ移し、しっぽの先は画像と一緒に回す。
            b.origin = b.origin + recentered(BubbleLayout.bodyRect(b)); b.tail = pt(b.tail)
            return with(content: .bubble(b))
        case .image(var im):
            im.rect = rect(im.rect)
            im.source = im.source.transformed(by: t)
            return with(content: .image(im))
        case .unknown:
            return self
        }
    }
}

public extension Document {
    /// 元画像の向き・注釈・切り抜き範囲をまとめて変える。
    func transformed(by t: ImageTransform) -> Document {
        let size = pixelSize
        var d = self
        d.base = base.transformed(by: t)
        d.annotations = annotations.map { $0.transformed(by: t, in: size) }
        d.canvas.crop = canvas.crop.map { t.apply($0, in: size) }
        return d
    }

    /// 次に置く数字のスタンプの番号。
    var nextStampNumber: Int { nextStampNumber(for: .number) }

    /// 次に置く `kind` のスタンプの番号(同じ種類の最大値 + 1)。途中を消しても重ならない。
    /// 数字と英字は別に数える。記号・絵文字は進まないので常に 1。
    func nextStampNumber(for kind: StampKind) -> Int {
        guard kind.isSequential else { return 1 }
        let numbers = annotations.compactMap { a -> Int? in
            if case .stamp(let s) = a.content, s.kind == kind { return s.number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }
}

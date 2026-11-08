import CoreGraphics
import CoreText
import Foundation

/// 回転・反転済みの元画像と、モザイク・ぼかしの計算結果を覚えておく。
///
/// `@unchecked Sendable`:内部の辞書は `lock` で保護している。
public final class RenderCache: @unchecked Sendable {
    struct BaseKey: Hashable { let sha: String; let rotation: Rotation; let flipH: Bool; let flipV: Bool }
    /// 効果の範囲に重なる画像オーバーレイ。画像を動かしたら計算し直す。
    struct OverlayKey: Hashable { let image: BaseKey; let x, y, w, h: Double }
    struct EffectKey: Hashable { let base: BaseKey; let overlays: [OverlayKey]; let region: PixelRect; let mode: ObscureMode; let strength: Double }

    private let lock = NSLock()
    private var base: (key: BaseKey, image: CGImage)?
    private var effects: [EffectKey: CGImage] = [:]
    private var overlayImages: [BaseKey: CGImage] = [:]
    private var order: [EffectKey] = []
    private let limit: Int

    public init(limit: Int = 48) { self.limit = limit }

    static func key(_ b: BaseImage) -> BaseKey {
        BaseKey(sha: b.asset.sha256, rotation: b.rotation, flipH: b.flipH, flipV: b.flipV)
    }

    func transformedBase(_ b: BaseImage) -> CGImage {
        if b.isIdentity { return b.asset.cgImage }
        let k = Self.key(b)
        lock.lock(); defer { lock.unlock() }
        if let base, base.key == k { return base.image }
        let img = Renderer.transformed(b) ?? b.asset.cgImage
        base = (k, img)
        return img
    }

    /// 回転・反転を適用した画像オーバーレイ。
    func transformedOverlay(_ b: BaseImage) -> CGImage {
        if b.isIdentity { return b.asset.cgImage }
        let k = Self.key(b)
        lock.lock(); defer { lock.unlock() }
        if let hit = overlayImages[k] { return hit }
        let img = Renderer.transformed(b) ?? b.asset.cgImage
        if overlayImages.count >= 16 { overlayImages.removeAll() }
        overlayImages[k] = img
        return img
    }

    func effect(_ k: EffectKey, make: () -> CGImage?) -> CGImage? {
        lock.lock()
        if let hit = effects[k] { lock.unlock(); return hit }
        lock.unlock()
        guard let img = make() else { return nil }
        lock.lock(); defer { lock.unlock() }
        effects[k] = img
        order.append(k)
        while order.count > limit { effects.removeValue(forKey: order.removeFirst()) }
        return img
    }
}

/// 画面表示と書き出しで共通の描画処理。
///
/// 渡す context は「元画像のピクセル座標・左上原点・y 下向き」にしておく(flipped な NSView はそのままで良い)。
/// 順序:元画像(回転・反転済み)→ 効果(モザイク・ぼかし)→ 図形を重なり順に。効果を先に描くので、図形がぼけない。
public enum Renderer {
    public static func draw(_ doc: Document, in ctx: CGContext, cache: RenderCache) {
        drawBackdrop(doc, in: ctx, cache: cache)
        drawForeground(doc, in: ctx, cache: cache)
    }

    /// 回転・反転を適用した元画像。
    public static func baseImage(_ b: BaseImage, cache: RenderCache) -> CGImage { cache.transformedBase(b) }

    public static func drawBase(_ doc: Document, in ctx: CGContext, cache: RenderCache) {
        drawImage(cache.transformedBase(doc.base), in: CGRect(origin: .zero, size: doc.pixelSize), ctx)
    }

    /// 下の層:元画像 → 画像オーバーレイ → 効果 → ハイライター。
    /// ハイライターの乗算を画面でも書き出しと同じにするため、元画像も同じ context に描く。
    public static func drawBackdrop(_ doc: Document, in ctx: CGContext, cache: RenderCache,
                                    dirty: CGRect? = nil, excluding: Set<UUID> = []) {
        drawBase(doc, in: ctx, cache: cache)
        let visible = visibleAnnotations(doc, dirty: dirty, excluding: excluding)
        for g in [RenderGroup.image, .effect, .highlight] {
            for a in visible where a.content.renderGroup == g {
                if g == .effect { drawEffect(a, doc, ctx, cache) } else { drawShape(a, in: ctx, cache: cache) }
            }
        }
    }

    /// 上の層:図形・文字を重なり順に。
    public static func drawForeground(_ doc: Document, in ctx: CGContext, cache: RenderCache,
                                      dirty: CGRect? = nil, excluding: Set<UUID> = []) {
        for a in visibleAnnotations(doc, dirty: dirty, excluding: excluding) where a.content.renderGroup == .shape {
            drawShape(a, in: ctx, cache: cache)
        }
    }

    /// 元画像を除いた注釈すべて(効果 → 図形)。`dirty` を渡すと、そこに掛からない注釈は飛ばす。
    public static func drawAnnotations(_ doc: Document, in ctx: CGContext, cache: RenderCache,
                                       dirty: CGRect? = nil, excluding: Set<UUID> = []) {
        let visible = visibleAnnotations(doc, dirty: dirty, excluding: excluding)
        for g in RenderGroup.allCases {
            for a in visible where a.content.renderGroup == g {
                if g == .effect { drawEffect(a, doc, ctx, cache) } else { drawShape(a, in: ctx, cache: cache) }
            }
        }
    }

    static func visibleAnnotations(_ doc: Document, dirty: CGRect?, excluding: Set<UUID>) -> [Annotation] {
        doc.annotations.filter { a in
            !a.hidden && !excluding.contains(a.id) && (dirty.map { a.bounds.intersects($0) } ?? true)
        }
    }

    /// 書き出し用の画像。切り抜きと `outputScale` を適用し、効果は焼き込む。
    public static func makeImage(_ doc: Document, cache: RenderCache = RenderCache()) -> CGImage? {
        let crop = doc.effectiveCrop
        let scale = doc.canvas.outputScale > 0 ? doc.canvas.outputScale : 1
        let w = max(1, Int((crop.width * scale).rounded())), h = max(1, Int((crop.height * scale).rounded()))
        guard let ctx = makeContext(width: w, height: h, colorSpace: colorSpace(for: doc.base.asset.cgImage)) else { return nil }
        ctx.scaleBy(x: CGFloat(w) / crop.width, y: CGFloat(h) / crop.height)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        ctx.clip(to: crop)
        draw(doc, in: ctx, cache: cache)
        return ctx.makeImage()
    }

    // MARK: - 部品

    static func drawEffect(_ a: Annotation, _ doc: Document, _ ctx: CGContext, _ cache: RenderCache) {
        guard case .obscure(let spec) = a.content,
              let region = PixelRect(spec.rect, within: doc.pixelSize) else { return }
        // 画像オーバーレイは効果より下にあるので、重なる分は一緒に伏せる。
        let overlays: [ImageSpec] = doc.annotations.compactMap { o in
            guard !o.hidden, case .image(let im) = o.content, im.rect.standardized.intersects(region.cgRect) else { return nil }
            return im
        }
        let key = RenderCache.EffectKey(
            base: RenderCache.key(doc.base),
            overlays: overlays.map { .init(image: RenderCache.key($0.source), x: $0.rect.minX, y: $0.rect.minY, w: $0.rect.width, h: $0.rect.height) },
            region: region, mode: spec.mode, strength: spec.strength)
        let img = cache.effect(key) {
            let base = cache.transformedBase(doc.base)
            if overlays.isEmpty {
                return ObscureRenderer.render(base, region: region, mode: spec.mode, strength: spec.strength)
            }
            guard let source = composite(base, overlays, region, cache) else { return nil }
            return ObscureRenderer.render(source, region: PixelRect(x: 0, y: 0, width: region.width, height: region.height),
                                          mode: spec.mode, strength: spec.strength)
        }
        if let img { drawImage(img, in: region.cgRect, ctx) }
    }

    /// `region` の範囲だけ、元画像に画像オーバーレイを重ねた画像。
    static func composite(_ base: CGImage, _ overlays: [ImageSpec], _ region: PixelRect, _ cache: RenderCache) -> CGImage? {
        guard let ctx = makeContext(width: region.width, height: region.height, colorSpace: colorSpace(for: base)) else { return nil }
        ctx.translateBy(x: -CGFloat(region.x), y: -CGFloat(region.y))
        drawImage(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height), ctx)
        for im in overlays { drawImage(cache.transformedOverlay(im.source), in: im.rect.standardized, ctx) }
        return ctx.makeImage()
    }

    public static func drawShape(_ a: Annotation, in ctx: CGContext, cache: RenderCache = RenderCache()) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.content {
        case .arrow(let s):
            ctx.setFillColor(s.color.cgColor)
            ctx.setStrokeColor(s.color.cgColor)
            if s.dash != .solid {
                drawDashedArrow(s, in: ctx)
                return
            }
            switch s.head {
            case .tapered:
                guard let p = ArrowPath.tapered(from: s.from, to: s.to, width: s.width) else { return }
                ctx.addPath(p)
                ctx.fillPath()
            case .open:
                guard let p = ArrowPath.open(from: s.from, to: s.to, width: s.width) else { return }
                ctx.setLineWidth(max(2, CGFloat(s.width) * 0.5))
                ctx.addPath(p)
                ctx.strokePath()
            }
        case .line(let s):
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.setLineDash(phase: 0, lengths: s.dash.lengths(width: CGFloat(s.width)))
            ctx.strokeLineSegments(between: [s.from, s.to])
        case .rect(let s):
            let r = s.rect.standardized
            if let fill = s.fill { ctx.setFillColor(fill.cgColor); ctx.fill(r) }
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.setLineDash(phase: 0, lengths: s.dash.lengths(width: CGFloat(s.width)))
            ctx.stroke(r)
        case .ellipse(let s):
            let r = s.rect.standardized
            if let fill = s.fill { ctx.setFillColor(fill.cgColor); ctx.fillEllipse(in: r) }
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.setLineDash(phase: 0, lengths: s.dash.lengths(width: CGFloat(s.width)))
            ctx.strokeEllipse(in: r)
        case .text(let s):
            TextLayout.draw(s, in: ctx)
        case .highlighter(let s):
            // 本物の蛍光ペンのように乗算で塗り、下の文字を潰さない。
            ctx.setBlendMode(.multiply)
            strokeFreehand(s, in: ctx)
        case .pen(let s):
            strokeFreehand(s, in: ctx)
        case .stamp(let s):
            drawStamp(s, in: ctx)
        case .image(let s):
            drawImage(cache.transformedOverlay(s.source), in: s.rect.standardized, ctx)
        case .obscure, .unknown:
            break
        }
    }

    /// 破線の矢印:軸は破線、矢じり(と付け根から先端までの芯)は実線。線の太さは開いた矢じりと同じ。
    static func drawDashedArrow(_ s: ArrowSpec, in ctx: CGContext) {
        guard let parts = ArrowPath.dashedParts(from: s.from, to: s.to, width: s.width) else { return }
        let lw = max(2, CGFloat(s.width) * 0.5)
        ctx.setLineWidth(lw)
        ctx.setLineDash(phase: 0, lengths: s.dash.lengths(width: lw))
        ctx.strokeLineSegments(between: [s.from, parts.shaftEnd])
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.addPath(parts.head)
        ctx.strokePath()
    }

    /// 点列を、隣り合う点の中点を通る2次曲線でなめらかにつないで描く。
    static func strokeFreehand(_ s: StrokeSpec, in ctx: CGContext) {
        guard let first = s.points.first else { return }
        let w = CGFloat(s.width)
        if s.points.count == 1 {
            ctx.setFillColor(s.color.cgColor)
            ctx.fillEllipse(in: CGRect(x: first.x - w / 2, y: first.y - w / 2, width: w, height: w))
            return
        }
        let path = CGMutablePath()
        path.move(to: first)
        for i in 1..<s.points.count {
            let p = s.points[i - 1], q = s.points[i]
            let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            if i == 1 { path.addLine(to: mid) } else { path.addQuadCurve(to: mid, control: p) }
        }
        path.addLine(to: s.points[s.points.count - 1])
        ctx.setStrokeColor(s.color.cgColor)
        ctx.setLineWidth(w)
        ctx.setLineDash(phase: 0, lengths: s.dash.lengths(width: w))
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// 色で塗った丸に白い番号。白い縁で、どの背景でも輪郭が分かるようにする。
    static func drawStamp(_ s: StampSpec, in ctx: CGContext) {
        let d = CGFloat(s.diameter)
        let r = CGRect(x: s.center.x - d / 2, y: s.center.y - d / 2, width: d, height: d)
        ctx.setFillColor(s.color.cgColor)
        ctx.fillEllipse(in: r)
        let edge = max(1, d * 0.07)
        ctx.setStrokeColor(RGBAColor.white.cgColor)
        ctx.setLineWidth(edge)
        ctx.strokeEllipse(in: r.insetBy(dx: edge / 2, dy: edge / 2))

        let label = String(s.number)
        let font = TextLayout.font(size: Double(d * (label.count > 2 ? 0.4 : label.count == 2 ? 0.48 : 0.56)), bold: true)
        let ink: RGBAColor = s.color == .white ? .black : .white
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink.cgColor]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, label as CFString, attrs as CFDictionary)!)
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: s.center.x - glyphs.midX, y: s.center.y + glyphs.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// 左上原点・y 下向きのビットマップ context。
    public static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace? = nil) -> CGContext? {
        guard let ctx = CGContext(
            data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// y 下向きの context に画像を正立で描く。
    public static func drawImage(_ img: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: rect)
        ctx.restoreGState()
    }

    /// 元画像の RGB 色空間が使えればそれを(Display P3 を sRGB に潰さないため)、だめなら sRGB。
    public static func colorSpace(for image: CGImage) -> CGColorSpace {
        if let cs = image.colorSpace, cs.model == .rgb, cs.supportsOutput { return cs }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// 回転・反転を適用した元画像。
    static func transformed(_ b: BaseImage) -> CGImage? {
        let src = b.asset.cgImage
        let w = CGFloat(src.width), h = CGFloat(src.height)
        let out = b.pixelSize
        guard let ctx = makeContext(width: Int(out.width), height: Int(out.height), colorSpace: colorSpace(for: src)) else { return nil }
        // 反転は回転の後にかける。concatenate は後から足したものが先に効く。
        if b.flipH { ctx.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: out.width, ty: 0)) }
        if b.flipV { ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: out.height)) }
        switch b.rotation {
        case .r0: break
        case .r90: ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
        case .r180: ctx.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
        case .r270: ctx.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
        }
        ctx.interpolationQuality = .none
        drawImage(src, in: CGRect(x: 0, y: 0, width: w, height: h), ctx)
        return ctx.makeImage()
    }
}

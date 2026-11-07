import CoreGraphics
import Foundation

/// 回転・反転済みの元画像と、モザイク・ぼかしの計算結果を覚えておく。
///
/// `@unchecked Sendable`:内部の辞書は `lock` で保護している。
public final class RenderCache: @unchecked Sendable {
    struct BaseKey: Hashable { let sha: String; let rotation: Rotation; let flipH: Bool; let flipV: Bool }
    struct EffectKey: Hashable { let base: BaseKey; let region: PixelRect; let mode: ObscureMode; let strength: Double }

    private let lock = NSLock()
    private var base: (key: BaseKey, image: CGImage)?
    private var effects: [EffectKey: CGImage] = [:]
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
        drawBase(doc, in: ctx, cache: cache)
        drawAnnotations(doc, in: ctx, cache: cache)
    }

    /// 回転・反転を適用した元画像。画面の下地レイヤーに載せる用。
    public static func baseImage(_ b: BaseImage, cache: RenderCache) -> CGImage { cache.transformedBase(b) }

    public static func drawBase(_ doc: Document, in ctx: CGContext, cache: RenderCache) {
        drawImage(cache.transformedBase(doc.base), in: CGRect(origin: .zero, size: doc.pixelSize), ctx)
    }

    /// 効果と図形を描く。`dirty` を渡すと、そこに掛からない注釈は飛ばす。`excluding` は描かない注釈(文字の編集中など)。
    public static func drawAnnotations(_ doc: Document, in ctx: CGContext, cache: RenderCache,
                                       dirty: CGRect? = nil, excluding: Set<UUID> = []) {
        let visible = doc.annotations.filter { a in
            !a.hidden && !excluding.contains(a.id) && (dirty.map { a.bounds.intersects($0) } ?? true)
        }
        for a in visible where a.content.isEffect { drawEffect(a, doc, ctx, cache) }
        for a in visible where !a.content.isEffect { drawShape(a, in: ctx) }
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
        let key = RenderCache.EffectKey(base: RenderCache.key(doc.base), region: region, mode: spec.mode, strength: spec.strength)
        let img = cache.effect(key) {
            ObscureRenderer.render(cache.transformedBase(doc.base), region: region, mode: spec.mode, strength: spec.strength)
        }
        if let img { drawImage(img, in: region.cgRect, ctx) }
    }

    public static func drawShape(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.content {
        case .arrow(let s):
            ctx.setFillColor(s.color.cgColor)
            ctx.setStrokeColor(s.color.cgColor)
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
            ctx.strokeLineSegments(between: [s.from, s.to])
        case .rect(let s):
            let r = s.rect.standardized
            if let fill = s.fill { ctx.setFillColor(fill.cgColor); ctx.fill(r) }
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.stroke(r)
        case .ellipse(let s):
            let r = s.rect.standardized
            if let fill = s.fill { ctx.setFillColor(fill.cgColor); ctx.fillEllipse(in: r) }
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.strokeEllipse(in: r)
        case .text(let s):
            TextLayout.draw(s, in: ctx)
        case .obscure, .unknown:
            break
        }
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

import AppKit
import KakiireCore

/// キャンバスへの入力を受け取る相手(EditorWindowController)。
protocol CanvasDelegate: AnyObject {
    var displayedDocument: Document { get }
    var selection: Set<UUID> { get }
    var marquee: CGRect? { get }
    var editingTextID: UUID? { get }
    /// 文字を入力中の吹き出し(入力欄の文字に合わせた大きさ)。入力欄の下に、文字を除いて描く。
    var editingBubble: BubbleSpec? { get }
    /// 切り抜きツールで調整中の範囲。
    var pendingCrop: CGRect? { get }
    func canvasMouseDown(_ p: CGPoint, _ event: NSEvent)
    func canvasMouseDragged(_ p: CGPoint, _ event: NSEvent)
    func canvasMouseUp(_ p: CGPoint, _ event: NSEvent)
    func canvasKeyDown(_ event: NSEvent) -> Bool
    func canvasCursor(at p: CGPoint) -> NSCursor
    func canvasDrop(_ pb: NSPasteboard, at p: CGPoint) -> Bool
    /// 右クリック(control クリック)で出すメニュー。
    func canvasMenu(at p: CGPoint) -> NSMenu?
}

/// 元画像のピクセル座標をそのまま座標系にしたビュー(左上原点・1pt = 1px)。拡大縮小は NSScrollView に任せる。
///
/// 下の `BackdropView` が元画像・画像オーバーレイ・効果・ハイライターを、前面の `AnnotationOverlay` が
/// 図形・選択枠を描く。どちらも変わった範囲だけ描き直す。ハイライターの乗算が画面と書き出しで同じになるよう、
/// 元画像は下の層と同じ context に描く。
///
/// 切り抜き後は `viewport`(切り抜き範囲)だけを見せる。子ビューは画像全体の大きさのまま、原点をずらして置く。
final class CanvasView: NSView {
    let backdrop = BackdropView()
    let overlay = AnnotationOverlay()
    private(set) var imageSize: CGSize = .zero
    private(set) var viewport: CGRect = .zero

    override var isFlipped: Bool { true }

    init(delegate: CanvasDelegate, cache: RenderCache) {
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        backdrop.delegate = delegate
        backdrop.cache = cache
        overlay.delegate = delegate
        overlay.cache = cache
        addSubview(backdrop)
        addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 画像の大きさと、見せる範囲を合わせる。
    func layout(imageSize: CGSize, viewport: CGRect) {
        let changed = imageSize != self.imageSize
        self.imageSize = imageSize
        self.viewport = viewport
        setFrameSize(viewport.size)
        let r = CGRect(origin: CGPoint(x: -viewport.minX, y: -viewport.minY), size: imageSize)
        backdrop.frame = r
        overlay.frame = r
        if changed { redrawAll() }
    }

    func redrawAll() {
        backdrop.needsDisplay = true
        overlay.needsDisplay = true
    }
}

/// 下の層。元画像・画像オーバーレイ・効果・ハイライター。
final class BackdropView: NSView {
    weak var delegate: CanvasDelegate?
    var cache = RenderCache()

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let d = delegate, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        Renderer.drawBackdrop(d.displayedDocument, in: ctx, cache: cache, dirty: dirtyRect)
    }

    // 入力は前面の AnnotationOverlay が受ける。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AnnotationOverlay: NSView {
    weak var delegate: CanvasDelegate?
    var cache = RenderCache()
    private var trackingArea: NSTrackingArea?

    /// 方眼を重ねるか。画面だけに描き、`Renderer` を通さないので書き出しには入らない。
    var showsGrid = Preferences.showsGrid {
        didSet { needsDisplay = true }
    }

    /// ドラッグ中にカーソルの近くへ出す大きさ(「760 × 560」など)。`at` はカーソルの位置(画像のピクセル座標)。
    var sizeBadge: (text: String, at: CGPoint)? {
        didSet {
            invalidate(oldValue.map { badgeRect($0.text, at: $0.at) } ?? .null)
            invalidate(sizeBadge.map { badgeRect($0.text, at: $0.at) } ?? .null)
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + PasteboardImage.dataTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 画面上の `points` ポイントを、キャンバス(画像ピクセル)上の長さに換算する。
    func canvasLength(_ points: CGFloat) -> CGFloat {
        let scale = convert(NSSize(width: 1, height: 1), to: nil).width
        return points / max(scale, 0.0001)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let d = delegate, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let doc = d.displayedDocument
        if showsGrid { drawGrid(origin: doc.effectiveCrop.origin, imageSize: doc.pixelSize, dirty: dirtyRect, ctx) }
        var excluded: Set<UUID> = []
        if let id = d.editingTextID { excluded.insert(id) }
        Renderer.drawForeground(doc, in: ctx, cache: cache, dirty: dirtyRect, excluding: excluded)
        if let b = d.editingBubble { BubbleLayout.draw(b, in: ctx, drawsText: false) }
        drawSelection(doc, d.selection, ctx)
        if let crop = d.pendingCrop { drawCropGuide(crop, imageSize: doc.pixelSize, ctx) }
        if let m = d.marquee {
            ctx.saveGState()
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(canvasLength(1))
            ctx.fill(m)
            ctx.stroke(m)
            ctx.restoreGState()
        }
        if let b = sizeBadge { drawBadge(b.text, at: b.at, ctx) }
    }

    /// 細い線の間隔の候補(画像のピクセル)。画面上で `minGridPoints` 以上あく最小の候補を使い、5本ごとに濃い線を引く。
    private static let gridSteps: [CGFloat] = [10, 20, 50, 100, 200, 500, 1000]
    private static let minGridPoints: CGFloat = 8

    /// 方眼を図形の下に描く。原点は見せている範囲(切り抜き後は切り抜きの左上)に合わせ、書き出し後の座標で数えやすくする。
    /// 白い画面にも暗い画面にも見えるよう、中間の灰色を半透明で引く。
    private func drawGrid(origin: CGPoint, imageSize: CGSize, dirty: CGRect, _ ctx: CGContext) {
        let onePoint = canvasLength(1)
        guard let i = Self.gridSteps.firstIndex(where: { $0 / onePoint >= Self.minGridPoints }) else { return }
        let minor = Self.gridSteps[i]
        let major = minor * 5
        let area = dirty.intersection(CGRect(origin: .zero, size: imageSize))
        guard !area.isNull, !area.isEmpty else { return }

        // 濃い線と重なる位置の細い線は引かない(重ねると濃さが変わるため)。
        func lines(_ step: CGFloat, skipping skip: CGFloat?) -> [CGPoint] {
            var pts: [CGPoint] = []
            func isSkipped(_ v: CGFloat) -> Bool {
                guard let skip else { return false }
                return abs((v / skip).rounded() * skip - v) < 0.5
            }
            var x = origin.x + ((area.minX - origin.x) / step).rounded(.up) * step
            while x <= area.maxX {
                if !isSkipped(x - origin.x) { pts += [CGPoint(x: x, y: area.minY), CGPoint(x: x, y: area.maxY)] }
                x += step
            }
            var y = origin.y + ((area.minY - origin.y) / step).rounded(.up) * step
            while y <= area.maxY {
                if !isSkipped(y - origin.y) { pts += [CGPoint(x: area.minX, y: y), CGPoint(x: area.maxX, y: y)] }
                y += step
            }
            return pts
        }

        ctx.saveGState()
        ctx.setLineWidth(onePoint)
        ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.12).cgColor)
        ctx.strokeLineSegments(between: lines(minor, skipping: major))
        ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.28).cgColor)
        ctx.strokeLineSegments(between: lines(major, skipping: nil))
        ctx.restoreGState()
    }

    private static let badgeFontSize: CGFloat = 15

    private func badgeAttributes() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: canvasLength(Self.badgeFontSize), weight: .semibold),
         .foregroundColor: NSColor.white]
    }

    /// 札の範囲。カーソルの右下に置き、見えている範囲からはみ出すときは左や上へ回す。
    private func badgeRect(_ text: String, at p: CGPoint) -> CGRect {
        let size = (text as NSString).size(withAttributes: badgeAttributes())
        let padX = canvasLength(10), padY = canvasLength(5), gap = canvasLength(16)
        let w = size.width + padX * 2, h = size.height + padY * 2
        var r = CGRect(x: p.x + gap, y: p.y + gap, width: w, height: h)
        let vis = visibleRect
        if r.maxX > vis.maxX { r.origin.x = p.x - gap - w }
        if r.maxY > vis.maxY { r.origin.y = p.y - gap - h }
        return r
    }

    private func drawBadge(_ text: String, at p: CGPoint, _ ctx: CGContext) {
        let r = badgeRect(text, at: p)
        let radius = canvasLength(6)
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        NSGraphicsContext.saveGraphicsState()
        (text as NSString).draw(at: CGPoint(x: r.minX + canvasLength(10), y: r.minY + canvasLength(5)), withAttributes: badgeAttributes())
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelection(_ doc: Document, _ selection: Set<UUID>, _ ctx: CGContext) {
        let line = canvasLength(1)
        let hs = canvasLength(HandleMetrics.size)
        for a in doc.annotations where selection.contains(a.id) && !a.hidden {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(line)
            ctx.setLineDash(phase: 0, lengths: [line * 4, line * 3])
            if a.isTwoPoint {
                if let first = a.handles.first?.1, let last = a.handles.last?.1 {
                    ctx.strokeLineSegments(between: [first, last])
                }
            } else {
                ctx.stroke(a.bounds.insetBy(dx: -line * 2, dy: -line * 2))
            }
            ctx.setLineDash(phase: 0, lengths: [])
            for (_, p) in a.handles { drawHandle(at: p, size: hs, line: line, ctx) }
            ctx.restoreGState()
        }
    }

    /// 切り抜きの外側を暗くし、三分割線と8つのつまみを描く。
    private func drawCropGuide(_ crop: CGRect, imageSize: CGSize, _ ctx: CGContext) {
        let line = canvasLength(1)
        let hs = canvasLength(HandleMetrics.cropSize)
        ctx.saveGState()
        ctx.addRect(CGRect(origin: .zero, size: imageSize))
        ctx.addRect(crop)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(line)
        for i in 1...2 {
            let x = crop.minX + crop.width * CGFloat(i) / 3, y = crop.minY + crop.height * CGFloat(i) / 3
            ctx.strokeLineSegments(between: [CGPoint(x: x, y: crop.minY), CGPoint(x: x, y: crop.maxY),
                                             CGPoint(x: crop.minX, y: y), CGPoint(x: crop.maxX, y: y)])
        }
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(line * 2)
        ctx.stroke(crop)
        for (_, p) in Annotation.rectHandlePoints(crop) { drawHandle(at: p, size: hs, line: line, ctx) }
        ctx.restoreGState()
    }

    /// つまみの画面上の大きさ(pt)。つかめる範囲は見た目より広くする。
    enum HandleMetrics {
        static let size: CGFloat = 12
        static let cropSize: CGFloat = 14
        static let hitRadius: CGFloat = 10
    }

    /// 白地に強調色の枠の、角の丸いつまみを描く。
    private func drawHandle(at p: CGPoint, size: CGFloat, line: CGFloat, _ ctx: CGContext) {
        let r = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        let path = CGPath(roundedRect: r, cornerWidth: size * 0.2, cornerHeight: size * 0.2, transform: nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(line * 1.5)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// 選択枠・つまみの分だけ広げて再描画を頼む。
    func invalidate(_ rect: CGRect) {
        guard !rect.isNull else { return }
        let pad = canvasLength(HandleMetrics.cropSize / 2 + 6)
        setNeedsDisplay(rect.insetBy(dx: -pad, dy: -pad))
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // mouseDown を上書きしているので、control クリックは自分でメニューに回す。
        if event.modifierFlags.contains(.control) {
            if let m = menu(for: event) { NSMenu.popUpContextMenu(m, with: event, for: self) }
            return
        }
        delegate?.canvasMouseDown(point(event), event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        return delegate?.canvasMenu(at: point(event))
    }

    override func mouseDragged(with event: NSEvent) {
        autoscroll(with: event)
        delegate?.canvasMouseDragged(point(event), event)
    }

    override func mouseUp(with event: NSEvent) { delegate?.canvasMouseUp(point(event), event) }

    override func keyDown(with event: NSEvent) {
        if delegate?.canvasKeyDown(event) != true { super.keyDown(with: event) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }

    /// ウインドウの縁ではカーソルを決めない。上書きするとウインドウのリサイズのカーソルが出なくなる。
    private func updateCursor(_ event: NSEvent) {
        if let content = window?.contentView {
            let p = content.convert(event.locationInWindow, from: nil)
            if !content.bounds.insetBy(dx: 6, dy: 6).contains(p) { return }
        }
        delegate?.canvasCursor(at: point(event)).set()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        PasteboardImage.hasImage(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        delegate?.canvasDrop(sender.draggingPasteboard, at: convert(sender.draggingLocation, from: nil)) ?? false
    }
}

/// 画像がウインドウより小さいとき、中央に置く。
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        let f = doc.frame
        if r.width > f.width { r.origin.x = (f.width - r.width) / 2 }
        if r.height > f.height { r.origin.y = (f.height - r.height) / 2 }
        return r
    }
}

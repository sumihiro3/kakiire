import AppKit
import KakiireCore

/// キャンバスへの入力を受け取る相手(EditorWindowController)。
protocol CanvasDelegate: AnyObject {
    var displayedDocument: Document { get }
    var selection: Set<UUID> { get }
    var marquee: CGRect? { get }
    var editingTextID: UUID? { get }
    func canvasMouseDown(_ p: CGPoint, _ event: NSEvent)
    func canvasMouseDragged(_ p: CGPoint, _ event: NSEvent)
    func canvasMouseUp(_ p: CGPoint, _ event: NSEvent)
    func canvasKeyDown(_ event: NSEvent) -> Bool
    func canvasCursor(at p: CGPoint) -> NSCursor
    func canvasDrop(_ pb: NSPasteboard) -> Bool
}

/// 元画像のピクセル座標をそのまま座標系にしたビュー(左上原点・1pt = 1px)。拡大縮小は NSScrollView に任せる。
///
/// 元画像は下のレイヤーに一度だけ載せ、効果・図形・選択枠は前面の `AnnotationOverlay` が変わった範囲だけ描き直す。
final class CanvasView: NSView {
    let baseView = NSView()
    let overlay = AnnotationOverlay()

    override var isFlipped: Bool { true }

    init(delegate: CanvasDelegate, cache: RenderCache) {
        super.init(frame: .zero)
        wantsLayer = true
        baseView.wantsLayer = true
        baseView.layer?.minificationFilter = .trilinear
        baseView.layer?.magnificationFilter = .nearest
        overlay.delegate = delegate
        overlay.cache = cache
        addSubview(baseView)
        addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 元画像(回転・反転済み)を差し替え、キャンバスの大きさを合わせる。
    func setBase(_ image: CGImage, size: CGSize) {
        let r = CGRect(origin: .zero, size: size)
        frame = r
        baseView.frame = r
        overlay.frame = r
        baseView.layer?.contents = image
        overlay.needsDisplay = true
    }
}

final class AnnotationOverlay: NSView {
    weak var delegate: CanvasDelegate?
    var cache = RenderCache()
    private var trackingArea: NSTrackingArea?

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
        var excluded: Set<UUID> = []
        if let id = d.editingTextID { excluded.insert(id) }
        Renderer.drawAnnotations(doc, in: ctx, cache: cache, dirty: dirtyRect, excluding: excluded)
        drawSelection(doc, d.selection, ctx)
        if let m = d.marquee {
            ctx.saveGState()
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(canvasLength(1))
            ctx.fill(m)
            ctx.stroke(m)
            ctx.restoreGState()
        }
    }

    private func drawSelection(_ doc: Document, _ selection: Set<UUID>, _ ctx: CGContext) {
        let line = canvasLength(1)
        let hs = canvasLength(8)
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
            for (_, p) in a.handles {
                let r = CGRect(x: p.x - hs / 2, y: p.y - hs / 2, width: hs, height: hs)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.stroke(r)
            }
            ctx.restoreGState()
        }
    }

    /// 選択枠・つまみの分だけ広げて再描画を頼む。
    func invalidate(_ rect: CGRect) {
        guard !rect.isNull else { return }
        let pad = canvasLength(12)
        setNeedsDisplay(rect.insetBy(dx: -pad, dy: -pad))
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        delegate?.canvasMouseDown(point(event), event)
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

    override func mouseMoved(with event: NSEvent) { delegate?.canvasCursor(at: point(event)).set() }
    override func cursorUpdate(with event: NSEvent) { delegate?.canvasCursor(at: point(event)).set() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        PasteboardImage.hasImage(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        delegate?.canvasDrop(sender.draggingPasteboard) ?? false
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

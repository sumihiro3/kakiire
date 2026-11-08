import AppKit
import KakiireCore
import KakiireIO

/// 1枚の画像を編集するウインドウ。ツールの操作を `EditOperation` に変えて文書に渡す。
///
/// ドラッグ中は `EditSession` の途中結果を表示だけし、マウスを離したときに1回の Undo として確定する。
final class EditorWindowController: NSWindowController, CanvasDelegate, NSMenuItemValidation {
    private enum Drag {
        case move(start: CGPoint)
        case resize(Annotation, Handle)
        case create(Tool, id: UUID, start: CGPoint)
        case freehand(Tool, id: UUID, points: [CGPoint])
        /// スタンプを置いて、離すまで動かせる。
        case place(Annotation, start: CGPoint)
        case marquee(start: CGPoint, initial: Set<UUID>)
        case cropHandle(Handle)
        case cropMove(start: CGPoint, original: CGRect)
        case cropNew(start: CGPoint)
    }

    /// `document` は addWindowController が設定するまで nil なので、生成時から使う参照を別に持つ。
    private unowned let kdoc: KakiireDocument

    let cache = RenderCache()
    private(set) var selection: Set<UUID> = [] { didSet { selectionChanged(oldValue) } }
    private(set) var marquee: CGRect? { didSet { overlay.invalidate((oldValue ?? .null).union(marquee ?? .null)) } }
    private(set) var tool: Tool = .arrow {
        didSet {
            if oldValue == .crop, tool != .crop { pendingCrop = nil }
            if tool == .crop, oldValue != .crop { pendingCrop = kdoc.content.effectiveCrop }
            refreshToolbar()
            updateViewport()
        }
    }
    /// 切り抜きツールで調整中の範囲。Return で確定、Esc で取り消す。
    private(set) var pendingCrop: CGRect? { didSet { overlay.needsDisplay = true; updateCropHint() } }
    var style = DrawingStyle()

    private var session: EditSession?
    private var drag: Drag?
    private var lastDisplayed: Document?
    private let text = TextEditing()

    private var scrollView: NSScrollView!
    private var canvas: CanvasView!
    private var overlay: AnnotationOverlay { canvas.overlay }
    private var backdrop: BackdropView { canvas.backdrop }
    private var toolBar: ToolBarView!
    private var layerPanel: LayerPanel!
    private let cropHint = NSTextField(labelWithString: "")
    private var layoutConstraints: [NSLayoutConstraint] = []

    var displayedDocument: Document { session?.current ?? kdoc.content }
    var editingTextID: UUID? { text.annotationID }
    var isReadOnly: Bool { kdoc.isReadOnly }

    init(document: KakiireDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isRestorable = false
        kdoc = document
        super.init(window: window)
        style.pixelScale = DrawingStyle.pixelScale(for: document.content.pixelSize)
        buildUI(window)
        document.onChange = { [weak self] old, new in self?.documentChanged(old, new) }
        reloadBase()
        layerPanel.reload()
        sizeWindowToFit()
        DispatchQueue.main.async { [weak self] in self?.zoomFit(nil) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func buildUI(_ window: NSWindow) {
        canvas = CanvasView(delegate: self, cache: cache)

        scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true
        scrollView.documentView = canvas
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        layerPanel = LayerPanel(controller: self)
        layerPanel.translatesAutoresizingMaskIntoConstraints = false

        cropHint.translatesAutoresizingMaskIntoConstraints = false
        cropHint.font = .systemFont(ofSize: 12, weight: .medium)
        cropHint.textColor = .white
        cropHint.drawsBackground = true
        cropHint.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        cropHint.isHidden = true

        window.contentView = NSView()
        window.contentView?.addSubview(scrollView)
        window.contentView?.addSubview(layerPanel)
        window.contentView?.addSubview(cropHint)
        installToolbar(Preferences.toolbarPosition)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: Preferences.didChange, object: nil)
    }

    /// ツールバー・レイヤーパネル・キャンバスを置き直す(設定の変更にすぐ追従する)。
    private func installToolbar(_ position: ToolbarPosition) {
        guard let root = window?.contentView else { return }
        toolBar?.removeFromSuperview()
        NSLayoutConstraint.deactivate(layoutConstraints)
        let bar = ToolBarView(controller: self, position: position)
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)
        toolBar = bar

        let showsLayers = Preferences.showsLayerPanel
        layerPanel.isHidden = !showsLayers
        let canvasTrailing = showsLayers ? layerPanel.leadingAnchor : root.trailingAnchor
        let top = position == .top ? bar.bottomAnchor : root.topAnchor
        var c: [NSLayoutConstraint] = [
            layerPanel.topAnchor.constraint(equalTo: top),
            layerPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            layerPanel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            layerPanel.widthAnchor.constraint(equalToConstant: LayerPanel.width),
            scrollView.topAnchor.constraint(equalTo: top),
            scrollView.trailingAnchor.constraint(equalTo: canvasTrailing),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            cropHint.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            cropHint.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -14),
        ]
        switch position {
        case .left:
            c += [
                bar.topAnchor.constraint(equalTo: root.topAnchor),
                bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                scrollView.leadingAnchor.constraint(equalTo: bar.trailingAnchor),
            ]
        case .top:
            c += [
                bar.topAnchor.constraint(equalTo: root.topAnchor),
                bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            ]
        }
        layoutConstraints = c
        NSLayoutConstraint.activate(c)
        window?.contentMinSize = minimumContentSize(for: bar)
        refreshToolbar()
    }

    /// ツールバー・パネルが欠けない最小の大きさ。
    private func minimumContentSize(for bar: ToolBarView) -> NSSize {
        let f = bar.fittingSize
        let panel = Preferences.showsLayerPanel ? LayerPanel.width : 0
        return bar.position == .left ? NSSize(width: f.width + 320 + panel, height: f.height)
                                     : NSSize(width: max(f.width, 560 + panel), height: f.height + 240)
    }

    @objc private func preferencesChanged() {
        let wantsLayers = Preferences.showsLayerPanel
        if toolBar.position != Preferences.toolbarPosition || layerPanel.isHidden == wantsLayers {
            installToolbar(Preferences.toolbarPosition)
        }
    }

    private func refreshToolbar() {
        toolBar?.update(tool: tool, style: style, target: styleTarget, dashEnabled: dashEnabled, enabled: !kdoc.isReadOnly)
    }

    private func sizeWindowToFit() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let size = canvas.viewport.size
        let backing = screen.backingScaleFactor
        let visible = screen.visibleFrame.insetBy(dx: 40, dy: 40)
        // Retina のスクショは画素が倍なので、ポイントに直して実寸相当の窓にする。
        let bar = toolBar.fittingSize
        let left = toolBar.position == .left
        let panel = Preferences.showsLayerPanel ? LayerPanel.width : 0
        let min = window.contentMinSize
        let w = clamp(size.width / backing + (left ? bar.width : 0) + panel, min.width, visible.width)
        let h = clamp(size.height / backing + (left ? 0 : bar.height), min.height, visible.height)
        window.setContentSize(NSSize(width: w, height: h))
        window.center()
    }

    private func reloadBase() {
        let doc = kdoc.content
        style.pixelScale = DrawingStyle.pixelScale(for: doc.pixelSize)
        lastDisplayed = doc
        updateViewport(force: true)
    }

    /// 見せる範囲:切り抜き中は画像全体、それ以外は切り抜き範囲。
    private func updateViewport(force: Bool = false) {
        guard let canvas else { return }
        let doc = displayedDocument
        let full = CGRect(origin: .zero, size: doc.pixelSize)
        let viewport = tool == .crop ? full : doc.effectiveCrop
        guard force || viewport != canvas.viewport || doc.pixelSize != canvas.imageSize else { return }
        let resized = viewport.size != canvas.viewport.size
        canvas.layout(imageSize: doc.pixelSize, viewport: viewport)
        canvas.redrawAll()
        if resized { DispatchQueue.main.async { [weak self] in self?.zoomFit(nil) } }
    }

    private func updateCropHint() {
        guard let r = pendingCrop else { cropHint.isHidden = true; return }
        cropHint.stringValue = "  \(Int(r.width.rounded())) × \(Int(r.height.rounded())) px    Return で確定 / Esc で取り消し  "
        cropHint.isHidden = false
    }

    // MARK: - 再描画

    /// 表示中の文書が変わったら、変わった注釈の範囲だけ描き直す。
    private func refreshCanvas() {
        let now = displayedDocument
        guard let prev = lastDisplayed else { canvas.redrawAll(); lastDisplayed = now; return }
        lastDisplayed = now
        if prev.base != now.base || prev.pixelSize != now.pixelSize {
            reloadBase()
            layerPanel.reload()
            return
        }
        if prev.canvas != now.canvas { updateViewport() }
        let old = Dictionary(prev.annotations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var front = CGRect.null, back = CGRect.null
        var seen: Set<UUID> = []
        func mark(_ a: Annotation, _ r: CGRect) {
            if a.content.renderGroup == .shape { front = front.union(r) } else { back = back.union(r) }
        }
        for a in now.annotations {
            seen.insert(a.id)
            if let o = old[a.id] {
                if o != a { mark(o, o.bounds); mark(a, a.bounds) }
            } else {
                mark(a, a.bounds)
            }
        }
        for (id, a) in old where !seen.contains(id) { mark(a, a.bounds) }
        // 画像オーバーレイが動くと、重なる効果の中身も変わる。
        if !back.isNull {
            for a in now.annotations where a.content.isEffect && a.bounds.intersects(back) { back = back.union(a.bounds) }
        }
        if prev.annotations.map(\.id) != now.annotations.map(\.id) {
            canvas.redrawAll()
        } else {
            overlay.invalidate(front)
            backdrop.setNeedsDisplay(back.isNull ? .zero : back.insetBy(dx: -2, dy: -2))
            // 選択枠は前面に描くので、下の層だけ変わった注釈も前面で描き直す。
            overlay.invalidate(back)
        }
    }

    private func documentChanged(_ old: Document, _ new: Document) {
        let ids = Set(new.annotations.map(\.id))
        if !selection.isSubset(of: ids) { selection = selection.intersection(ids) }
        refreshCanvas()
        toolBar.updateDragThumbnail()
        layerPanel.reload()
    }

    private func selectionChanged(_ old: Set<UUID>) {
        let doc = displayedDocument
        var r = CGRect.null
        for a in doc.annotations where old.contains(a.id) || selection.contains(a.id) { r = r.union(a.bounds) }
        overlay.invalidate(r)
        layerPanel?.syncSelection()
        if selection.count == 1, let id = selection.first, let a = doc.annotation(id) { adoptStyle(from: a) }
        refreshToolbar()
    }

    // MARK: - セッション

    private func beginSession() { session = EditSession(kdoc.content) }

    private func update(_ ops: [EditOperation]) {
        session?.update(ops)
        refreshCanvas()
    }

    private func commitSession(_ actionName: String) {
        guard let s = session else { return }
        session = nil
        if let result = s.commit() {
            kdoc.setContent(result.after, actionName: actionName)
        } else {
            refreshCanvas()
        }
    }

    private func cancelSession() {
        session = nil
        refreshCanvas()
    }

    /// 1回で終わる変更。
    private func apply(_ ops: [EditOperation], _ actionName: String) {
        kdoc.setContent(kdoc.content.applying(ops), actionName: actionName)
    }

    // MARK: - CanvasDelegate(マウス)

    func canvasMouseDown(_ p: CGPoint, _ event: NSEvent) {
        if kdoc.isReadOnly { NSSound.beep(); return }
        if text.isEditing { endTextEditing() }
        let doc = kdoc.content
        let tol = overlay.canvasLength(AnnotationOverlay.HandleMetrics.hitRadius)
        let shift = event.modifierFlags.contains(.shift)

        switch tool {
        case .select:
            for a in doc.annotations where selection.contains(a.id) && !a.locked {
                if let h = HitTesting.handle(at: p, of: a, tolerance: tol) {
                    beginSession()
                    drag = .resize(a, h)
                    return
                }
            }
            if let id = HitTesting.annotation(at: p, in: doc, tolerance: tol) {
                if event.clickCount == 2, let a = doc.annotation(id), case .text = a.content {
                    selection = [id]
                    beginTextEditing(existing: a)
                    return
                }
                if shift {
                    if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                } else if !selection.contains(id) {
                    selection = [id]
                }
                beginSession()
                drag = .move(start: p)
            } else {
                if !shift { selection = [] }
                drag = .marquee(start: p, initial: selection)
            }
        case .text:
            if let id = HitTesting.annotation(at: p, in: doc, tolerance: tol),
               let a = doc.annotation(id), case .text = a.content {
                selection = [id]
                beginTextEditing(existing: a)
            } else {
                beginTextEditing(newAt: p)
            }
        case .arrow, .line, .rect, .ellipse, .pixelate, .blur:
            selection = []
            beginSession()
            drag = .create(tool, id: UUID(), start: p)
        case .highlighter, .pen:
            selection = []
            beginSession()
            let id = UUID()
            drag = .freehand(tool, id: id, points: [p])
            updateFreehand(tool, id, [p])
        case .stamp:
            let content = AnnotationContent.stamp(StampSpec(center: p, number: doc.nextStampNumber, color: style.color, diameter: style.stampDiameter))
            let a = Annotation(name: doc.nextName(for: content), content: content)
            beginSession()
            update([.add(a)])
            selection = [a.id]
            drag = .place(a, start: p)
        case .crop:
            let crop = pendingCrop ?? doc.effectiveCrop
            if let h = Annotation.rectHandlePoints(crop).first(where: { (p - $0.1).length <= tol * 1.5 })?.0 {
                drag = .cropHandle(h)
            } else if crop.contains(p), crop.size != doc.pixelSize {
                // 画像全体のままなら動かしようがないので、ドラッグで新しい範囲を作る。
                drag = .cropMove(start: p, original: crop)
            } else {
                drag = .cropNew(start: p)
            }
        }
    }

    func canvasMouseDragged(_ p: CGPoint, _ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .move(let start):
            update([.move(selection, by: p - start)])
        case .resize(let a, let h):
            update([.replace(a.resized(h, to: p, constrain: shift))])
        case .create(let t, let id, let start):
            guard let content = style.content(for: t, from: start, to: p, constrain: shift) else { return }
            let a = Annotation(id: id, name: kdoc.content.nextName(for: content), content: content)
            update([.add(a)])
        case .freehand(let t, let id, var points):
            // Shift で始点からの直線。それ以外は画面で 1.5pt 以上動いたら点を足す。
            if shift {
                points = [points[0], p]
            } else if let last = points.last, (p - last).length >= overlay.canvasLength(1.5) {
                points.append(p)
            } else {
                return
            }
            drag = .freehand(t, id: id, points: points)
            updateFreehand(t, id, points)
        case .place(let a, let start):
            update([.add(a), .move([a.id], by: p - start)])
        case .marquee(let start, let initial):
            let r = CGRect(corner: start, p)
            marquee = r
            selection = initial.union(HitTesting.annotations(intersecting: r, in: kdoc.content))
        case .cropHandle(let h):
            if let c = pendingCrop { pendingCrop = clampToImage(Annotation.resize(c, h, p, shift)) }
        case .cropMove(let start, let original):
            pendingCrop = clampMove(original.offsetBy(dx: p.x - start.x, dy: p.y - start.y))
        case .cropNew(let start):
            pendingCrop = clampToImage(CGRect(corner: start, p))
        case nil:
            break
        }
    }

    private func updateFreehand(_ t: Tool, _ id: UUID, _ points: [CGPoint]) {
        guard let content = style.stroke(for: t, points: points) else { return }
        update([.add(Annotation(id: id, name: kdoc.content.nextName(for: content), content: content))])
    }

    func canvasMouseUp(_ p: CGPoint, _ event: NSEvent) {
        defer { drag = nil }
        switch drag {
        case .move:
            commitSession("移動")
        case .resize:
            commitSession("変形")
        case .create(let t, let id, _):
            guard let a = session?.current.annotation(id), isBigEnough(a) else { cancelSession(); return }
            commitSession("\(t.title)を追加")
            selection = [id]
        case .freehand(let t, _, _):
            commitSession("\(t.title)を追加")
        case .place:
            commitSession("スタンプを追加")
        case .marquee:
            marquee = nil
        case .cropNew:
            if let c = pendingCrop, c.width < overlay.canvasLength(4) || c.height < overlay.canvasLength(4) {
                pendingCrop = kdoc.content.effectiveCrop
            }
        case .cropHandle, .cropMove, nil:
            break
        }
    }

    private func clampToImage(_ r: CGRect) -> CGRect {
        let full = CGRect(origin: .zero, size: kdoc.content.pixelSize)
        let c = r.standardized.intersection(full)
        return c.isNull ? r.standardized : c
    }

    private func clampMove(_ r: CGRect) -> CGRect {
        let size = kdoc.content.pixelSize
        return CGRect(x: clamp(r.minX, 0, size.width - r.width), y: clamp(r.minY, 0, size.height - r.height),
                      width: r.width, height: r.height)
    }

    /// クリックしただけの極小の図形は作らない。
    private func isBigEnough(_ a: Annotation) -> Bool {
        let min = overlay.canvasLength(3)
        switch a.content {
        case .arrow(let s): return (s.to - s.from).length >= min
        case .line(let s): return (s.to - s.from).length >= min
        case .rect(let s), .ellipse(let s): return s.rect.width >= min && s.rect.height >= min
        case .obscure(let s): return s.rect.width >= min && s.rect.height >= min
        default: return true
        }
    }

    func canvasCursor(at p: CGPoint) -> NSCursor {
        switch tool {
        case .select:
            let doc = kdoc.content
            let tol = overlay.canvasLength(AnnotationOverlay.HandleMetrics.hitRadius)
            for a in doc.annotations where selection.contains(a.id) {
                if HitTesting.handle(at: p, of: a, tolerance: tol) != nil { return .crosshair }
            }
            return HitTesting.annotation(at: p, in: doc, tolerance: tol) != nil ? .openHand : .arrow
        case .text: return .iBeam
        case .crop:
            if let c = pendingCrop, c.contains(p), c.size != kdoc.content.pixelSize { return .openHand }
            return .crosshair
        default: return .crosshair
        }
    }

    func canvasDrop(_ pb: NSPasteboard) -> Bool {
        KakiireDocumentController.current.openFromDrop(pb)
    }

    // MARK: - キー

    func canvasKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty else { return false }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            delete(nil)
            return true
        case 53: // esc
            if tool == .crop { tool = .select } else if !selection.isEmpty { selection = [] } else { tool = .select }
            return true
        case 123, 124, 125, 126: // ← → ↓ ↑
            nudge(event)
            return true
        case 36, 76: // return
            if tool == .crop { applyCrop(nil); return true }
            if selection.count == 1, let a = kdoc.content.annotation(selection.first!), case .text = a.content {
                beginTextEditing(existing: a)
                return true
            }
            return false
        default:
            if let chars = event.charactersIgnoringModifiers, let t = Tool.forKey(chars) {
                selectTool(t)
                return true
            }
            return false
        }
    }

    private func nudge(_ event: NSEvent) {
        guard !selection.isEmpty else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let v: CGVector = switch event.keyCode {
        case 123: CGVector(dx: -step, dy: 0)
        case 124: CGVector(dx: step, dy: 0)
        case 125: CGVector(dx: 0, dy: step)
        default: CGVector(dx: 0, dy: -step)
        }
        apply([.move(selection, by: v)], "移動")
    }

    // MARK: - テキスト

    private func beginTextEditing(existing a: Annotation) {
        guard case .text(let spec) = a.content else { return }
        text.begin(spec: spec, id: a.id, isNew: false, in: overlay) { [weak self] result in self?.finishText(result) }
        adoptStyle(from: a)
        refreshToolbar()
        overlay.invalidate(a.bounds)
    }

    private func beginTextEditing(newAt p: CGPoint) {
        let spec = TextSpec(origin: p, text: "", color: style.color, fontSize: style.fontSize, outline: style.outline)
        text.begin(spec: spec, id: UUID(), isNew: true, in: overlay) { [weak self] result in self?.finishText(result) }
        refreshToolbar()
    }

    private func endTextEditing() { text.end() }

    private func finishText(_ r: TextEditing.Result) {
        let doc = kdoc.content
        let trimmed = r.spec.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isNew {
            if !trimmed.isEmpty {
                let content = AnnotationContent.text(r.spec)
                apply([.add(Annotation(id: r.id, name: doc.nextName(for: content), content: content))], "テキストを追加")
                selection = [r.id]
            }
        } else if let old = doc.annotation(r.id) {
            if trimmed.isEmpty {
                apply([.remove([r.id])], "テキストを削除")
            } else {
                apply([.replace(old.with(content: .text(r.spec)))], "テキストを編集")
            }
            overlay.invalidate(old.bounds)
        }
        overlay.invalidate(TextLayout.bounds(r.spec))
        refreshToolbar()
        window?.makeFirstResponder(overlay)
    }

    // MARK: - ツールバー・メニューの操作

    func selectTool(_ t: Tool) {
        if text.isEditing { endTextEditing() }
        if t == .crop, kdoc.isReadOnly { NSSound.beep(); return }
        tool = t
        window?.makeFirstResponder(overlay)
    }

    @objc func selectToolFromMenu(_ sender: NSMenuItem) {
        if let t = Tool(rawValue: sender.tag) { selectTool(t) }
    }

    /// 次に描く注釈のスタイルを変え、選択中の注釈(編集中のテキストを含む)にも当てる。
    func setStyle(_ change: StyleChange) {
        style = style.merged(change)
        refreshToolbar()
        if text.isEditing {
            text.restyle { [style] spec in
                guard case .text(let s) = style.applying(change, to: Annotation(name: "", content: .text(spec))).content else { return spec }
                return s
            }
        }
        let doc = kdoc.content
        let ops = doc.annotations.filter { selection.contains($0.id) }.compactMap { a -> EditOperation? in
            let b = style.applying(change, to: a)
            return b == a ? nil : .replace(b)
        }
        if !ops.isEmpty { apply(ops, "スタイルを変更") }
    }

    /// 選択中(なければ今のツール)が文字なら、文字の大きさを1段変える。
    func stepFontSize(_ delta: Int) {
        guard styleTarget == .text else { NSSound.beep(); return }
        let next = min(max(style.fontIndex + delta, 0), FontSizes.steps.count - 1)
        if next == style.fontIndex { NSSound.beep(); return }
        setStyle(StyleChange(fontIndex: next))
    }

    @objc func biggerText(_ sender: Any?) { stepFontSize(1) }
    @objc func smallerText(_ sender: Any?) { stepFontSize(-1) }

    /// スタイルボタンが変える対象。編集中のテキスト・選択中の注釈・今のツールの順に決める。
    var styleTarget: StyleTarget {
        if text.isEditing { return .text }
        let selected = kdoc.content.annotations.filter { selection.contains($0.id) }.compactMap(\.content.styleTarget)
        if let first = selected.first, selected.allSatisfy({ $0 == first }) { return first }
        return tool.styleTarget
    }

    /// 線の種類を選べるか。選択中の注釈があればそれ、なければ今のツールで決める。
    var dashEnabled: Bool {
        if text.isEditing { return false }
        let selected = kdoc.content.annotations.filter { selection.contains($0.id) }
        if !selected.isEmpty { return selected.contains { $0.content.supportsDash } }
        return tool.supportsDash
    }

    /// 注釈を1つ選んだら、その文字の大きさ・袋文字・強さをスタイルボタンに映す。
    private func adoptStyle(from a: Annotation) {
        switch a.content {
        case .text(let s):
            style.fontIndex = FontSizes.nearestIndex(to: s.fontSize, pixelScale: style.pixelScale)
            style.outline = s.outline
        case .obscure(let s):
            let px = s.mode == .blur ? s.strength / 1.4 : s.strength
            style.obscureLevel = ObscureLevel.allCases.min { abs($0.pixelate * style.pixelScale - px) < abs($1.pixelate * style.pixelScale - px) } ?? .medium
        case .arrow(let s): style.dash = s.dash
        case .line(let s): style.dash = s.dash
        case .rect(let s), .ellipse(let s): style.dash = s.dash
        case .pen(let s): style.dash = s.dash
        default:
            return
        }
    }

    @objc func delete(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        apply([.remove(selection)], "削除")
    }

    @objc override func selectAll(_ sender: Any?) {
        tool = .select
        selection = Set(kdoc.content.annotations.filter { !$0.hidden && !$0.locked }.map(\.id))
    }

    /// ⌘C も仕上がり画像のコピーにする(注釈どうしのコピーは仕様外)。
    @objc func copy(_ sender: Any?) { copyImage(sender) }

    @objc func copyImage(_ sender: Any?) {
        do {
            try Exporter.copyToPasteboard(kdoc.content, cache: cache)
        } catch {
            presentError(error)
        }
    }

    private func pasteboardAsset() -> ImageAsset? {
        PasteboardImage.asset(.general)
            ?? PasteboardImage.imageFileURLs(.general).first.flatMap { try? ImageImport.asset(contentsOf: $0) }
    }

    /// 編集中の ⌘V:クリップボードの画像を画像オーバーレイとして、見えている範囲の中央に置く。
    @objc func paste(_ sender: Any?) {
        guard !kdoc.isReadOnly, let asset = pasteboardAsset() else { NSSound.beep(); return }
        let doc = kdoc.content
        let visible = overlay.visibleRect.intersection(doc.effectiveCrop)
        let area = visible.isNull || visible.isEmpty ? doc.effectiveCrop : visible
        // 見えている範囲の 6 割に収まるよう縮める(拡大はしない)。
        let size = asset.pixelSize
        let k = min(1, area.width * 0.6 / max(size.width, 1), area.height * 0.6 / max(size.height, 1))
        let w = size.width * k, h = size.height * k
        let rect = CGRect(x: (area.midX - w / 2).rounded(), y: (area.midY - h / 2).rounded(), width: w.rounded(), height: h.rounded())
        let content = AnnotationContent.image(ImageSpec(asset: asset, rect: rect))
        let a = Annotation(name: doc.nextName(for: content), content: content)
        apply([.add(a)], "画像を貼り付け")
        tool = .select
        selection = [a.id]
    }

    @objc func replaceBaseFromClipboard(_ sender: Any?) {
        guard !kdoc.isReadOnly, let asset = pasteboardAsset() else { NSSound.beep(); return }
        apply([.replaceBase(asset)], "元画像を置き換え")
    }

    @objc func exportImage(_ sender: Any?) {
        guard let window else { return }
        Exporter.runSavePanel(for: kdoc, cache: cache, window: window)
    }

    // MARK: - 画像メニュー

    @objc func rotateLeft(_ sender: Any?) { transform(.rotateCounterclockwise, "左に回転") }
    @objc func rotateRight(_ sender: Any?) { transform(.rotateClockwise, "右に回転") }
    @objc func flipHorizontal(_ sender: Any?) { transform(.flipHorizontal, "左右反転") }
    @objc func flipVertical(_ sender: Any?) { transform(.flipVertical, "上下反転") }

    private func transform(_ t: ImageTransform, _ name: String) {
        if tool == .crop { tool = .select }
        apply([.transform(t)], name)
    }

    @objc func startCrop(_ sender: Any?) { selectTool(.crop) }

    @objc func applyCrop(_ sender: Any?) {
        guard tool == .crop, let r = pendingCrop else { return }
        let rounded = CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
        tool = .select
        apply([.setCrop(rounded)], "切り抜き")
    }

    @objc func clearCrop(_ sender: Any?) {
        if tool == .crop { tool = .select }
        apply([.setCrop(nil)], "切り抜きを解除")
    }

    @objc func showImageSize(_ sender: Any?) {
        guard let window else { return }
        ImageSizeSheet.run(for: kdoc.content, on: window) { [weak self] scale in
            self?.apply([.setOutputScale(scale)], "画像サイズを変更")
        }
    }

    // MARK: - レイヤー(パネル・メニュー)

    @objc func toggleLayerPanel(_ sender: Any?) {
        Preferences.showsLayerPanel.toggle()
    }

    func selectLayers(_ ids: Set<UUID>) {
        if tool != .select { tool = .select }
        if selection != ids { selection = ids }
    }

    func setLayersHidden(_ ids: Set<UUID>, _ hidden: Bool) {
        apply([.setHidden(ids, hidden)], hidden ? "非表示" : "表示")
    }

    func setLayersLocked(_ ids: Set<UUID>, _ locked: Bool) {
        apply([.setLocked(ids, locked)], locked ? "ロック" : "ロック解除")
    }

    func renameLayer(_ id: UUID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, kdoc.content.annotation(id)?.name != trimmed else { return }
        apply([.rename(id, trimmed)], "名前を変更")
    }

    /// パネルの行の移動。別グループへの移動は受け付けない。
    @discardableResult
    func moveLayer(_ id: UUID, toRow row: Int) -> Bool {
        guard !kdoc.isReadOnly, let op = LayerList.move(id, toRow: row, in: kdoc.content) else { return false }
        apply([op], "重なり順を変更")
        return true
    }

    @objc func bringToFront(_ sender: Any?) { reorderSelection(LayerList.moveToFront, backFirst: true) }
    @objc func sendToBack(_ sender: Any?) { reorderSelection(LayerList.moveToBack, backFirst: false) }

    /// 複数選択でも相対順を保つよう、1つずつ適用しながら作る。
    /// 最前面へは背面側から、最背面へは前面側から動かす(最後に動かしたものが端に来るため)。
    private func reorderSelection(_ f: (UUID, Document) -> EditOperation?, backFirst: Bool) {
        var doc = kdoc.content
        var ops: [EditOperation] = []
        let rows = LayerList.rows(doc).filter(selection.contains)
        for id in backFirst ? rows.reversed() : rows {
            if let op = f(id, doc) { ops.append(op); doc = doc.applying(op) }
        }
        if !ops.isEmpty { apply(ops, "重なり順を変更") }
    }

    // MARK: - 表示

    @objc func zoomIn(_ sender: Any?) { zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { zoom(by: 0.8) }

    @objc func zoomActual(_ sender: Any?) {
        // 画像の1画素を画面の1画素に合わせる。
        let backing = window?.backingScaleFactor ?? 2
        scrollView.magnification = 1 / backing
    }

    @objc func zoomFit(_ sender: Any?) {
        let size = canvas.viewport.size
        let view = scrollView.contentSize
        guard size.width > 0, size.height > 0 else { return }
        let m = min(view.width / size.width, view.height / size.height, 1)
        scrollView.magnification = clamp(m, scrollView.minMagnification, scrollView.maxMagnification)
    }

    private func zoom(by f: CGFloat) {
        scrollView.magnification = clamp(scrollView.magnification * f, scrollView.minMagnification, scrollView.maxMagnification)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let editable = !kdoc.isReadOnly
        switch item.action {
        case #selector(delete(_:)): return editable && !selection.isEmpty
        case #selector(paste(_:)), #selector(replaceBaseFromClipboard(_:)): return editable && PasteboardImage.hasImage(.general)
        case #selector(selectToolFromMenu(_:)):
            item.state = item.tag == tool.rawValue ? .on : .off
            return editable || item.tag == Tool.select.rawValue
        case #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flipHorizontal(_:)),
             #selector(flipVertical(_:)), #selector(startCrop(_:)), #selector(showImageSize(_:)):
            return editable
        case #selector(applyCrop(_:)): return editable && tool == .crop
        case #selector(clearCrop(_:)): return editable && kdoc.content.canvas.crop != nil
        case #selector(bringToFront(_:)), #selector(sendToBack(_:)): return editable && !selection.isEmpty
        case #selector(biggerText(_:)): return editable && styleTarget == .text && style.fontIndex < FontSizes.steps.count - 1
        case #selector(smallerText(_:)): return editable && styleTarget == .text && style.fontIndex > 0
        case #selector(toggleLayerPanel(_:)):
            item.title = Preferences.showsLayerPanel ? "レイヤーを隠す" : "レイヤーを表示"
            return true
        default: return true
        }
    }
}

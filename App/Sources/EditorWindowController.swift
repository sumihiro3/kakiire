import AppKit
import KakiireCore
import KakiireIO

/// 1枚の画像を編集するウインドウ。ツールの操作を `EditOperation` に変えて文書に渡す。
///
/// ドラッグ中は `EditSession` の途中結果を表示だけし、マウスを離したときに1回の Undo として確定する。
final class EditorWindowController: NSWindowController, NSWindowDelegate, CanvasDelegate, NSMenuItemValidation {
    private enum Drag {
        case move(start: CGPoint)
        case resize(Annotation, Handle)
        case create(Tool, id: UUID, start: CGPoint)
        case marquee(start: CGPoint, initial: Set<UUID>)
    }

    /// `document` は addWindowController が設定するまで nil なので、生成時から使う参照を別に持つ。
    private unowned let kdoc: KakiireDocument

    let cache = RenderCache()
    private(set) var selection: Set<UUID> = [] { didSet { selectionChanged(oldValue) } }
    private(set) var marquee: CGRect? { didSet { overlay.invalidate((oldValue ?? .null).union(marquee ?? .null)) } }
    private(set) var tool: Tool = .arrow { didSet { toolBar.update(tool: tool, style: style) } }
    var style = DrawingStyle()

    private var session: EditSession?
    private var drag: Drag?
    private var lastDisplayed: Document?
    private let text = TextEditing()

    private var scrollView: NSScrollView!
    private var canvas: CanvasView!
    private var overlay: AnnotationOverlay { canvas.overlay }
    private var toolBar: ToolBarView!

    var displayedDocument: Document { session?.current ?? kdoc.content }
    var editingTextID: UUID? { text.annotationID }

    init(document: KakiireDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isRestorable = false
        window.minSize = NSSize(width: 560, height: 320)
        kdoc = document
        super.init(window: window)
        style.pixelScale = DrawingStyle.pixelScale(for: document.content.pixelSize)
        buildUI(window)
        window.delegate = self
        document.onChange = { [weak self] old, new in self?.documentChanged(old, new) }
        reloadBase()
        sizeWindowToFit()
        DispatchQueue.main.async { [weak self] in self?.zoomFit(nil) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func buildUI(_ window: NSWindow) {
        toolBar = ToolBarView(controller: self)
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

        let root = NSView()
        for v in [toolBar!, scrollView!] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            toolBar.topAnchor.constraint(equalTo: root.topAnchor),
            toolBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
        toolBar.update(tool: tool, style: style)
    }

    private func sizeWindowToFit() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let size = kdoc.content.pixelSize
        let backing = screen.backingScaleFactor
        let visible = screen.visibleFrame.insetBy(dx: 40, dy: 40)
        // Retina のスクショは画素が倍なので、ポイントに直して実寸相当の窓にする。
        let w = clamp(size.width / backing, 560, visible.width)
        let h = clamp(size.height / backing + toolBar.fittingSize.height, 320, visible.height)
        window.setContentSize(NSSize(width: w, height: h))
        window.center()
    }

    private func reloadBase() {
        let doc = kdoc.content
        canvas.setBase(cache.transformedBaseImage(doc.base), size: doc.pixelSize)
        style.pixelScale = DrawingStyle.pixelScale(for: doc.pixelSize)
        lastDisplayed = doc
    }

    // MARK: - 再描画

    /// 表示中の文書が変わったら、変わった注釈の範囲だけ描き直す。
    private func refreshCanvas() {
        let now = displayedDocument
        guard let prev = lastDisplayed else { overlay.needsDisplay = true; lastDisplayed = now; return }
        lastDisplayed = now
        if prev.base != now.base {
            reloadBase()
            return
        }
        let old = Dictionary(prev.annotations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var dirty = CGRect.null
        var seen: Set<UUID> = []
        for a in now.annotations {
            seen.insert(a.id)
            if let o = old[a.id] {
                if o != a { dirty = dirty.union(o.bounds).union(a.bounds) }
            } else {
                dirty = dirty.union(a.bounds)
            }
        }
        for (id, a) in old where !seen.contains(id) { dirty = dirty.union(a.bounds) }
        // 重なり順だけが変わった場合も描き直す。
        if prev.annotations.map(\.id) != now.annotations.map(\.id) {
            overlay.needsDisplay = true
        } else {
            overlay.invalidate(dirty)
        }
    }

    private func documentChanged(_ old: Document, _ new: Document) {
        let ids = Set(new.annotations.map(\.id))
        if !selection.isSubset(of: ids) { selection = selection.intersection(ids) }
        refreshCanvas()
        toolBar.updateDragThumbnail()
    }

    private func selectionChanged(_ old: Set<UUID>) {
        let doc = displayedDocument
        var r = CGRect.null
        for a in doc.annotations where old.contains(a.id) || selection.contains(a.id) { r = r.union(a.bounds) }
        overlay.invalidate(r)
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
        if text.isEditing { endTextEditing() }
        let doc = kdoc.content
        let tol = overlay.canvasLength(6)
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
        case .marquee(let start, let initial):
            let r = CGRect(corner: start, p)
            marquee = r
            selection = initial.union(HitTesting.annotations(intersecting: r, in: kdoc.content))
        case nil:
            break
        }
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
        case .marquee:
            marquee = nil
        case nil:
            break
        }
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
            let tol = overlay.canvasLength(6)
            for a in doc.annotations where selection.contains(a.id) {
                if HitTesting.handle(at: p, of: a, tolerance: tol) != nil { return .crosshair }
            }
            return HitTesting.annotation(at: p, in: doc, tolerance: tol) != nil ? .openHand : .arrow
        case .text: return .iBeam
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
            if !selection.isEmpty { selection = [] } else { tool = .select }
            return true
        case 123, 124, 125, 126: // ← → ↓ ↑
            nudge(event)
            return true
        case 36, 76: // return
            if selection.count == 1, let a = kdoc.content.annotation(selection.first!), case .text = a.content {
                beginTextEditing(existing: a)
                return true
            }
            return false
        default:
            if let chars = event.charactersIgnoringModifiers, let t = Tool.forKey(chars) {
                tool = t
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
        overlay.invalidate(a.bounds)
    }

    private func beginTextEditing(newAt p: CGPoint) {
        let spec = TextSpec(origin: p, text: "", color: style.color, fontSize: style.fontSize)
        text.begin(spec: spec, id: UUID(), isNew: true, in: overlay) { [weak self] result in self?.finishText(result) }
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
        window?.makeFirstResponder(overlay)
    }

    // MARK: - ツールバー・メニューの操作

    func selectTool(_ t: Tool) {
        if text.isEditing { endTextEditing() }
        tool = t
        window?.makeFirstResponder(overlay)
    }

    @objc func selectToolFromMenu(_ sender: NSMenuItem) {
        if let t = Tool(rawValue: sender.tag) { selectTool(t) }
    }

    func setColor(_ c: RGBAColor) {
        style.color = c
        toolBar.update(tool: tool, style: style)
        restyleSelection(color: c, weight: nil)
    }

    func setWeight(_ w: Weight) {
        style.weight = w
        toolBar.update(tool: tool, style: style)
        restyleSelection(color: nil, weight: w)
    }

    private func restyleSelection(color: RGBAColor?, weight: Weight?) {
        let doc = kdoc.content
        let ops = doc.annotations.filter { selection.contains($0.id) }.map {
            EditOperation.replace(style.applying(color: color, weight: weight, to: $0))
        }
        if !ops.isEmpty { apply(ops, "スタイルを変更") }
    }

    @objc func delete(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        apply([.remove(selection)], "削除")
    }

    @objc override func selectAll(_ sender: Any?) {
        tool = .select
        selection = Set(kdoc.content.annotations.filter { !$0.hidden && !$0.locked }.map(\.id))
    }

    /// 編集中の注釈のコピーはフェーズ3。いまは ⌘C も仕上がり画像のコピーにする。
    @objc func copy(_ sender: Any?) { copyImage(sender) }

    @objc func copyImage(_ sender: Any?) {
        do {
            try Exporter.copyToPasteboard(kdoc.content, cache: cache)
            kdoc.markExported()
        } catch {
            presentError(error)
        }
    }

    /// 編集中の ⌘V:元画像をクリップボードの画像に差し替える(注釈は残す)。
    @objc func paste(_ sender: Any?) {
        guard let asset = PasteboardImage.asset(.general)
            ?? PasteboardImage.imageFileURLs(.general).first.flatMap({ try? ImageImport.asset(contentsOf: $0) }),
            let window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "元画像をクリップボードの画像に置き換えますか？"
        alert.informativeText = "注釈はそのまま残ります。新しいウインドウで開くこともできます。"
        alert.addButton(withTitle: "置き換える")
        alert.addButton(withTitle: "新しいウインドウで開く")
        alert.addButton(withTitle: "キャンセル")
        alert.beginSheetModal(for: window) { [weak self] r in
            guard let self else { return }
            switch r {
            case .alertFirstButtonReturn: self.apply([.replaceBase(asset)], "元画像を置き換え")
            case .alertSecondButtonReturn: KakiireDocumentController.current.openNew(asset: asset, name: "クリップボード")
            default: break
            }
        }
    }

    @objc func exportImage(_ sender: Any?) {
        guard let window else { return }
        Exporter.runSavePanel(for: kdoc, cache: cache, window: window)
    }

    @objc func zoomIn(_ sender: Any?) { zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { zoom(by: 0.8) }

    @objc func zoomActual(_ sender: Any?) {
        // 画像の1画素を画面の1画素に合わせる。
        let backing = window?.backingScaleFactor ?? 2
        scrollView.magnification = 1 / backing
    }

    @objc func zoomFit(_ sender: Any?) {
        let size = kdoc.content.pixelSize
        let view = scrollView.contentSize
        guard size.width > 0, size.height > 0 else { return }
        let m = min(view.width / size.width, view.height / size.height, 1)
        scrollView.magnification = clamp(m, scrollView.minMagnification, scrollView.maxMagnification)
    }

    private func zoom(by f: CGFloat) {
        scrollView.magnification = clamp(scrollView.magnification * f, scrollView.minMagnification, scrollView.maxMagnification)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(delete(_:)): return !selection.isEmpty
        case #selector(paste(_:)): return PasteboardImage.hasImage(.general)
        case #selector(selectToolFromMenu(_:)):
            item.state = item.tag == tool.rawValue ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: - 閉じる確認

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if text.isEditing { endTextEditing() }
        guard kdoc.hasUnexportedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "書き出していない変更があります"
        alert.informativeText = "この版では編集内容を保存できません。閉じると変更は失われます。"
        alert.addButton(withTitle: "書き出す…")
        alert.addButton(withTitle: "閉じる")
        alert.addButton(withTitle: "キャンセル")
        alert.beginSheetModal(for: sender) { [weak self] r in
            guard let self else { return }
            switch r {
            case .alertFirstButtonReturn: self.exportImage(nil)
            case .alertSecondButtonReturn: self.kdoc.markExported(); sender.close()
            default: break
            }
        }
        return false
    }
}

extension RenderCache {
    /// 回転・反転を適用した元画像(キャンバスの下地に使う)。
    func transformedBaseImage(_ b: BaseImage) -> CGImage { Renderer.baseImage(b, cache: self) }
}

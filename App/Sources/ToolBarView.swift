import AppKit
import KakiireCore

/// 編集ツールバー:ツール・色・太さ・ドラッグで持ち出し・書き出し。
///
/// ツールは1列(上に置くときは1行)に並べる。色や太さのように選択肢が複数あるものは、
/// 今の値を示すボタン1つにまとめ、押すとメニューで選ばせる。
final class ToolBarView: NSView {
    let position: ToolbarPosition
    private weak var controller: EditorWindowController?
    private var toolButtons: [ToolButton] = []
    private let colorButton = ChoiceButton()
    private let weightButton = ChoiceButton()
    private let dashButton = ChoiceButton()
    private var target: StyleTarget = .stroke
    private var arrowOutlineEnabled = false
    private let dragOut = DragOutView()
    private var style = DrawingStyle()

    /// `controller` が nil なら、起動画面用に押せない状態で作る(撮影ボタンだけ使える)。
    init(controller: EditorWindowController?, position: ToolbarPosition) {
        self.controller = controller
        self.position = position
        super.init(frame: .zero)
        let vertical = position == .left

        toolButtons = Tool.allCases.map { t in
            let b = ToolButton(tool: t)
            b.target = self
            b.action = #selector(toolChanged(_:))
            return b
        }

        colorButton.toolTip = String(localized: "色(選択中の注釈にも当たる)")
        colorButton.setAccessibilityLabel(String(localized: "色"))
        colorButton.drawContent = { [unowned self] rect in Self.drawSwatch(self.style.color, in: rect.insetBy(dx: 5, dy: 5)) }
        colorButton.makeMenu = { [unowned self] in self.colorMenu() }

        weightButton.drawContent = { [unowned self] rect in
            switch self.target {
            case .stroke: Self.drawWeight(self.style.weight, in: rect)
            case .text: Self.drawFontSize(FontSizes.steps[self.style.fontIndex], outline: self.style.outline, in: rect)
            case .obscure: Self.drawLevel(self.style.obscureLevel, in: rect)
            case .image: Self.drawImageFrame(self.style.imageFrame, shadow: self.style.imageShadow, in: rect)
            }
        }
        weightButton.makeMenu = { [unowned self] in self.weightMenu() }

        dashButton.toolTip = String(localized: "線の種類(実線・破線・点線・一点鎖線)")
        dashButton.setAccessibilityLabel(String(localized: "線の種類"))
        dashButton.drawContent = { [unowned self] rect in Self.drawDash(self.style.dash, in: rect) }
        dashButton.makeMenu = { [unowned self] in self.dashMenu() }

        dragOut.controller = controller
        dragOut.toolTip = String(localized: "ドラッグして画像を持ち出す(PNG)")

        let export = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: String(localized: "書き出す"))!,
                              target: controller, action: #selector(EditorWindowController.exportImage(_:)))
        export.bezelStyle = .texturedRounded
        export.toolTip = String(localized: "書き出す…(⇧⌘E)")
        export.isEnabled = controller != nil
        dragOut.isHidden = controller == nil

        let capture = NSButton(image: NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: String(localized: "スクリーンショットを撮る"))!,
                               target: nil, action: controller == nil ? #selector(AppDelegate.newFromScreenshot(_:)) : #selector(EditorWindowController.insertScreenshot(_:)))
        capture.bezelStyle = .texturedRounded
        // 起動画面(controller なし)では新しいウインドウで開き、編集画面では今の画像に重ねる。
        capture.toolTip = controller == nil
            ? String(localized: "スクリーンショットを撮る")
            : String(localized: "スクリーンショットを撮って、この画像に重ねる(新しいウインドウで開くには ⌃⇧⌘N)")

        let tools = NSStackView(views: toolButtons)
        tools.orientation = vertical ? .vertical : .horizontal
        tools.spacing = 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: vertical ? .vertical : .horizontal)

        let stack = NSStackView(views: [tools, separator(vertical), colorButton, weightButton, dashButton, spacer, capture, dragOut, export])
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .centerX : .centerY
        stack.spacing = vertical ? 8 : 10
        stack.setCustomSpacing(vertical ? 10 : 12, after: tools)
        stack.edgeInsets = vertical ? NSEdgeInsets(top: 10, left: 6, bottom: 12, right: 6)
                                    : NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragOut.widthAnchor.constraint(equalToConstant: 28),
            dragOut.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func separator(_ vertical: Bool) -> NSView {
        let box = NSBox()
        box.boxType = .separator
        if vertical {
            box.widthAnchor.constraint(equalToConstant: 24).isActive = true
        } else {
            box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }
        return box
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        if position == .left {
            NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        } else {
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
    }

    func update(tool: Tool, style: DrawingStyle, target: StyleTarget, dashEnabled: Bool,
                arrowOutlineEnabled: Bool, enabled: Bool = true) {
        self.style = style
        self.target = target
        self.arrowOutlineEnabled = arrowOutlineEnabled
        switch target {
        case .stroke:
            weightButton.toolTip = arrowOutlineEnabled ? String(localized: "線の太さ・白い縁取り") : String(localized: "線の太さ")
            weightButton.setAccessibilityLabel(String(localized: "太さ"))
        case .text:
            weightButton.toolTip = String(localized: "文字の大きさ・袋文字(⌥⌘+ / ⌥⌘-)")
            weightButton.setAccessibilityLabel(String(localized: "文字の大きさ"))
        case .obscure:
            weightButton.toolTip = String(localized: "モザイク・ぼかしの強さ")
            weightButton.setAccessibilityLabel(String(localized: "強さ"))
        case .image:
            weightButton.toolTip = String(localized: "画像の枠線・影(枠の色は色ボタンで変える)")
            weightButton.setAccessibilityLabel(String(localized: "枠線"))
        }
        for b in toolButtons { b.isChosen = b.tool == tool; b.isEnabled = enabled || b.tool == .select }
        colorButton.isEnabled = enabled
        weightButton.isEnabled = enabled
        dashButton.isEnabled = enabled && dashEnabled
        dashButton.needsDisplay = true
        colorButton.needsDisplay = true
        weightButton.needsDisplay = true
    }

    func updateDragThumbnail() { dragOut.needsDisplay = true }

    @objc private func toolChanged(_ sender: ToolButton) { controller?.selectTool(sender.tool) }

    // MARK: - 選択肢のメニュー

    private func colorMenu() -> NSMenu {
        let menu = NSMenu()
        for c in RGBAColor.palette {
            let item = NSMenuItem(title: c.japaneseName, action: #selector(colorChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.hex
            item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
                Self.drawSwatch(c, in: r.insetBy(dx: 1, dy: 1))
                return true
            }
            item.state = c == style.color ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func weightMenu() -> NSMenu {
        switch target {
        case .stroke: strokeMenu()
        case .text: fontMenu()
        case .obscure: levelMenu()
        case .image: imageFrameMenu()
        }
    }

    private func strokeMenu() -> NSMenu {
        let menu = NSMenu()
        for w in Weight.allCases {
            let item = NSMenuItem(title: w.menuTitle, action: #selector(weightChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = w.rawValue
            item.image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { r in
                Self.drawWeight(w, in: r)
                return true
            }
            item.state = w == style.weight ? .on : .off
            menu.addItem(item)
        }
        if arrowOutlineEnabled {
            menu.addItem(.separator())
            let outline = NSMenuItem(title: String(localized: "白い縁取り"), action: #selector(arrowOutlineToggled(_:)), keyEquivalent: "")
            outline.target = self
            outline.state = style.arrowOutline ? .on : .off
            outline.toolTip = String(localized: "矢印のまわりを縁取りして、暗い画像や同じ色の多い画像でも目立たせる")
            menu.addItem(outline)
        }
        return menu
    }

    private func fontMenu() -> NSMenu {
        let menu = NSMenu()
        for (i, pt) in FontSizes.steps.enumerated() {
            let item = NSMenuItem(title: "\(Int(pt)) pt", action: #selector(fontChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == style.fontIndex ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let outline = NSMenuItem(title: String(localized: "袋文字"), action: #selector(outlineToggled(_:)), keyEquivalent: "")
        outline.target = self
        outline.state = style.outline ? .on : .off
        outline.toolTip = String(localized: "文字のまわりを縁取りして、どんな背景でも読めるようにする")
        menu.addItem(outline)
        return menu
    }

    private func levelMenu() -> NSMenu {
        let menu = NSMenu()
        for l in ObscureLevel.allCases {
            let item = NSMenuItem(title: l.menuTitle, action: #selector(levelChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = l.rawValue
            item.image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { r in
                Self.drawLevel(l, in: r)
                return true
            }
            item.state = l == style.obscureLevel ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func imageFrameMenu() -> NSMenu {
        let menu = NSMenu()
        for f in ImageFrame.allCases {
            let item = NSMenuItem(title: f.menuTitle, action: #selector(imageFrameChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = f.rawValue
            item.image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { r in
                Self.drawImageFrame(f, shadow: false, in: r)
                return true
            }
            item.state = f == style.imageFrame ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let shadow = NSMenuItem(title: String(localized: "影を付ける"), action: #selector(imageShadowToggled(_:)), keyEquivalent: "")
        shadow.target = self
        shadow.state = style.imageShadow ? .on : .off
        menu.addItem(shadow)
        return menu
    }

    private func send(_ change: StyleChange) { controller?.setStyle(change) }

    private func dashMenu() -> NSMenu {
        let menu = NSMenu()
        for d in LineDash.allCases {
            let item = NSMenuItem(title: d.menuTitle, action: #selector(dashChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = d.rawValue
            item.image = NSImage(size: NSSize(width: 28, height: 14), flipped: false) { r in
                Self.drawDash(d, in: r)
                return true
            }
            item.state = d == style.dash ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func dashChosen(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let d = LineDash(rawValue: raw) { send(StyleChange(dash: d)) }
    }

    @objc private func fontChosen(_ sender: NSMenuItem) { send(StyleChange(fontIndex: sender.tag)) }
    @objc private func outlineToggled(_ sender: NSMenuItem) { send(StyleChange(outline: !style.outline)) }
    @objc private func arrowOutlineToggled(_ sender: NSMenuItem) { send(StyleChange(arrowOutline: !style.arrowOutline)) }
    @objc private func imageFrameChosen(_ sender: NSMenuItem) {
        if let f = ImageFrame(rawValue: sender.tag) { send(StyleChange(imageFrame: f)) }
    }
    @objc private func imageShadowToggled(_ sender: NSMenuItem) { send(StyleChange(imageShadow: !style.imageShadow)) }
    @objc private func levelChosen(_ sender: NSMenuItem) {
        if let l = ObscureLevel(rawValue: sender.tag) { send(StyleChange(obscureLevel: l)) }
    }

    @objc private func colorChosen(_ sender: NSMenuItem) {
        if let hex = sender.representedObject as? String, let c = RGBAColor(hex: hex) { send(StyleChange(color: c)) }
    }

    @objc private func weightChosen(_ sender: NSMenuItem) {
        if let w = Weight(rawValue: sender.tag) { send(StyleChange(weight: w)) }
    }

    // MARK: - 描画部品

    static func drawSwatch(_ c: RGBAColor, in r: NSRect) {
        let dot = NSBezierPath(ovalIn: r)
        (NSColor(cgColor: c.cgColor) ?? .black).setFill()
        dot.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }

    /// 文字の大きさを数字で示す。袋文字のときは縁取りして描く。
    static func drawFontSize(_ pt: Double, outline: Bool, in r: NSRect) {
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        if outline { attrs[.strokeColor] = NSColor.labelColor; attrs[.strokeWidth] = 3; attrs[.foregroundColor] = NSColor.clear }
        let str = NSAttributedString(string: "\(Int(pt))", attributes: attrs)
        let s = str.size()
        str.draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
    }

    /// 強さをマス目の細かさで示す(強いほどマスが大きい)。
    static func drawLevel(_ l: ObscureLevel, in r: NSRect) {
        let box = NSRect(x: r.midX - 8, y: r.midY - 8, width: 16, height: 16)
        let n = [4, 3, 2][l.rawValue]
        let cell = box.width / CGFloat(n)
        for y in 0..<n {
            for x in 0..<n {
                (x + y).isMultiple(of: 2) ? NSColor.labelColor.setFill() : NSColor.tertiaryLabelColor.setFill()
                NSRect(x: box.minX + CGFloat(x) * cell, y: box.minY + CGFloat(y) * cell, width: cell, height: cell).fill()
            }
        }
    }

    /// 画像の枠線の太さと影を、小さな写真の絵で示す。
    static func drawImageFrame(_ f: ImageFrame, shadow: Bool, in r: NSRect) {
        let box = NSRect(x: r.midX - 9, y: r.midY - 6, width: 18, height: 13)
        if shadow {
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(rect: box.offsetBy(dx: 1.5, dy: -1.5)).fill()
        }
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(rect: box).fill()
        if f != .none {
            NSColor.labelColor.setStroke()
            let w = CGFloat([0, 1, 2, 3.5][f.rawValue])
            let p = NSBezierPath(rect: box.insetBy(dx: w / 2, dy: w / 2))
            p.lineWidth = w
            p.stroke()
        }
    }

    /// 線の種類を横線で示す。
    static func drawDash(_ d: LineDash, in r: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX + 4, y: r.midY))
        path.line(to: NSPoint(x: r.maxX - 4, y: r.midY))
        path.lineWidth = 2
        path.lineCapStyle = .round
        let lengths = d.lengths(width: 2)
        if !lengths.isEmpty { path.setLineDash(lengths, count: lengths.count, phase: 0) }
        NSColor.labelColor.setStroke()
        path.stroke()
    }

    /// 太さを横線の太さで示す。
    static func drawWeight(_ w: Weight, in r: NSRect) {
        let h: CGFloat = [1.5, 3, 5][w.rawValue]
        let line = NSRect(x: r.minX + 5, y: r.midY - h / 2, width: r.width - 10, height: h)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: line, xRadius: h / 2, yRadius: h / 2).fill()
    }
}

/// 今の値を描き、押すと選択肢のメニューを出すボタン。
final class ChoiceButton: NSControl {
    var drawContent: ((NSRect) -> Void)?
    var makeMenu: (() -> NSMenu)?
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.35) }
        drawContent?(bounds)
        // 右下の小さな三角で「押すと選べる」ことを示す。
        let t = NSBezierPath()
        t.move(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + 1))
        t.line(to: NSPoint(x: bounds.maxX - 6, y: bounds.minY + 1))
        t.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + 6))
        t.close()
        NSColor.secondaryLabelColor.setFill()
        t.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let menu = makeMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.maxX + 2, y: bounds.maxY), in: self)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let menu = makeMenu?() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.maxX + 2, y: bounds.maxY), in: self)
        return true
    }
}

/// ツールの四角いボタン。選択中は強調色で塗る。
final class ToolButton: NSControl {
    let tool: Tool
    var isChosen = false { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    init(tool: Tool) {
        self.tool = tool
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        toolTip = "\(tool.title) (\(tool.key.uppercased()))\n\(tool.hint)"
        setAccessibilityLabel(tool.title)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isChosen {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        guard let symbol = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title) else { return }
        let tint: NSColor = isChosen ? .white : (isEnabled ? .labelColor : .tertiaryLabelColor)
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular).applying(.init(paletteColors: [tint]))
        let img = symbol.withSymbolConfiguration(cfg) ?? symbol
        let s = img.size
        img.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled { sendAction(action, to: target) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        sendAction(action, to: target)
        return true
    }
}

extension RGBAColor {
    /// メニューに出す色の名前。
    var japaneseName: String {
        switch self {
        case .pink: String(localized: "ピンク")
        case .red: String(localized: "赤")
        case .orange: String(localized: "オレンジ")
        case .yellow: String(localized: "黄")
        case .green: String(localized: "緑")
        case .blue: String(localized: "青")
        case .purple: String(localized: "紫")
        case .black: String(localized: "黒")
        case .white: String(localized: "白")
        default: hex
        }
    }
}

extension Weight {
    var menuTitle: String { [String(localized: "細い"), String(localized: "ふつう"), String(localized: "太い")][rawValue] }
}

extension ImageFrame {
    var menuTitle: String {
        [String(localized: "枠線なし"), String(localized: "細い枠線"), String(localized: "ふつうの枠線"), String(localized: "太い枠線")][rawValue]
    }
}

extension LineDash {
    var menuTitle: String {
        switch self {
        case .solid: String(localized: "実線")
        case .dashed: String(localized: "破線")
        case .dotted: String(localized: "点線")
        case .dashDot: String(localized: "一点鎖線")
        }
    }
}

extension ObscureLevel {
    var menuTitle: String { [String(localized: "弱い"), String(localized: "ふつう"), String(localized: "強い")][rawValue] }
}

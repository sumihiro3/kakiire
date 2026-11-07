import AppKit
import KakiireCore

/// 編集ツールバー:ツール・色・太さ・ドラッグで持ち出し・書き出し。
///
/// 左に置くときは縦長にまとめる(ツールは2列、色は3列)。上に置くときは1行に並べる。
final class ToolBarView: NSView {
    let position: ToolbarPosition
    private weak var controller: EditorWindowController?
    private var toolButtons: [ToolButton] = []
    private var swatches: [ColorSwatch] = []
    private let weights = NSSegmentedControl()
    private let dragOut = DragOutView()

    init(controller: EditorWindowController, position: ToolbarPosition) {
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
        swatches = RGBAColor.palette.map { c in
            let s = ColorSwatch(color: c)
            s.target = self
            s.action = #selector(colorChanged(_:))
            return s
        }

        weights.segmentCount = Weight.allCases.count
        weights.trackingMode = .selectOne
        weights.controlSize = vertical ? .small : .regular
        for w in Weight.allCases { weights.setLabel(w.title, forSegment: w.rawValue) }
        weights.target = self
        weights.action = #selector(weightChanged)
        weights.toolTip = "線の太さ・文字の大きさ"

        dragOut.controller = controller
        dragOut.toolTip = "ドラッグして画像を持ち出す(PNG)"

        let export: NSButton
        if vertical, let img = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "書き出す") {
            export = NSButton(image: img, target: controller, action: #selector(EditorWindowController.exportImage(_:)))
            export.bezelStyle = .texturedRounded
            export.toolTip = "書き出す…(⇧⌘E)"
        } else {
            export = NSButton(title: "書き出す…", target: controller, action: #selector(EditorWindowController.exportImage(_:)))
            export.bezelStyle = .rounded
        }

        let toolGrid = Self.grid(toolButtons, columns: vertical ? 2 : toolButtons.count, spacing: 2)
        let colorGrid = Self.grid(swatches, columns: vertical ? 3 : swatches.count, spacing: 4)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: vertical ? .vertical : .horizontal)
        let tail = NSStackView(views: [dragOut, export])
        tail.orientation = vertical ? .vertical : .horizontal
        tail.spacing = 8

        let stack = NSStackView(views: [toolGrid, separator(vertical), colorGrid, weights, spacer, tail])
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .centerX : .centerY
        stack.spacing = vertical ? 12 : 14
        stack.edgeInsets = vertical ? NSEdgeInsets(top: 10, left: 8, bottom: 12, right: 8)
                                    : NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragOut.widthAnchor.constraint(equalToConstant: 30),
            dragOut.heightAnchor.constraint(equalToConstant: 26),
        ])
        if vertical { weights.widthAnchor.constraint(equalTo: toolGrid.widthAnchor).isActive = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func grid(_ views: [NSView], columns: Int, spacing: CGFloat) -> NSGridView {
        let rows = stride(from: 0, to: views.count, by: columns).map { start -> [NSView] in
            var row = Array(views[start..<min(start + columns, views.count)])
            while row.count < columns { row.append(NSGridCell.emptyContentView) }
            return row
        }
        let g = NSGridView(views: rows)
        g.rowSpacing = spacing
        g.columnSpacing = spacing
        return g
    }

    private func separator(_ vertical: Bool) -> NSView {
        let box = NSBox()
        box.boxType = .separator
        if vertical { box.widthAnchor.constraint(equalToConstant: 56).isActive = true }
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

    func update(tool: Tool, style: DrawingStyle, enabled: Bool = true) {
        for b in toolButtons { b.isChosen = b.tool == tool; b.isEnabled = enabled || b.tool == .select }
        weights.selectedSegment = style.weight.rawValue
        weights.isEnabled = enabled
        for s in swatches { s.isChosen = s.color == style.color; s.isEnabled = enabled }
    }

    func updateDragThumbnail() { dragOut.needsDisplay = true }

    @objc private func toolChanged(_ sender: ToolButton) { controller?.selectTool(sender.tool) }

    @objc private func colorChanged(_ sender: ColorSwatch) { controller?.setColor(sender.color) }

    @objc private func weightChanged() {
        if let w = Weight(rawValue: weights.selectedSegment) { controller?.setWeight(w) }
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
        toolTip = "\(tool.title) (\(tool.key.uppercased()))"
        setAccessibilityLabel(tool.title)
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
}

/// 色の丸ボタン。
final class ColorSwatch: NSControl {
    let color: RGBAColor
    var isChosen = false { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    init(color: RGBAColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        toolTip = color.hex
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 20).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        let dot = NSBezierPath(ovalIn: r)
        (NSColor(cgColor: color.cgColor) ?? .black).withAlphaComponent(isEnabled ? 1 : 0.35).setFill()
        dot.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        dot.lineWidth = 1
        dot.stroke()
        if isChosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled { sendAction(action, to: target) }
    }
}

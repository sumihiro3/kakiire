import AppKit
import KakiireCore

/// 上部の道具バー:ツール・色・太さ・ドラッグで持ち出し・書き出し。
final class ToolBarView: NSView {
    private weak var controller: EditorWindowController?
    private let tools = NSSegmentedControl()
    private let weights = NSSegmentedControl()
    private var swatches: [ColorSwatch] = []
    private let dragOut = DragOutView()

    init(controller: EditorWindowController) {
        self.controller = controller
        super.init(frame: .zero)

        tools.segmentCount = Tool.allCases.count
        tools.trackingMode = .selectOne
        for t in Tool.allCases {
            let img = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title)
            if let img { tools.setImage(img, forSegment: t.rawValue) } else { tools.setLabel(t.title, forSegment: t.rawValue) }
            tools.setToolTip("\(t.title) (\(t.key.uppercased()))", forSegment: t.rawValue)
            tools.setWidth(32, forSegment: t.rawValue)
        }
        tools.target = self
        tools.action = #selector(toolChanged)

        swatches = RGBAColor.palette.map { c in
            let s = ColorSwatch(color: c)
            s.target = self
            s.action = #selector(colorChanged(_:))
            return s
        }

        weights.segmentCount = Weight.allCases.count
        weights.trackingMode = .selectOne
        for w in Weight.allCases { weights.setLabel(w.title, forSegment: w.rawValue) }
        weights.target = self
        weights.action = #selector(weightChanged)
        weights.toolTip = "線の太さ・文字の大きさ"

        dragOut.controller = controller
        dragOut.toolTip = "ドラッグして画像を持ち出す(PNG)"

        let export = NSButton(title: "書き出す…", target: controller, action: #selector(EditorWindowController.exportImage(_:)))
        export.bezelStyle = .rounded

        let colors = NSStackView(views: swatches)
        colors.spacing = 4
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [tools, colors, weights, spacer, dragOut, export])
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    func update(tool: Tool, style: DrawingStyle) {
        tools.selectedSegment = tool.rawValue
        weights.selectedSegment = style.weight.rawValue
        for s in swatches { s.isChosen = s.color == style.color }
    }

    func updateDragThumbnail() { dragOut.needsDisplay = true }

    @objc private func toolChanged() {
        if let t = Tool(rawValue: tools.selectedSegment) { controller?.selectTool(t) }
    }

    @objc private func colorChanged(_ sender: ColorSwatch) { controller?.setColor(sender.color) }

    @objc private func weightChanged() {
        if let w = Weight(rawValue: weights.selectedSegment) { controller?.setWeight(w) }
    }
}

/// 色の丸ボタン。
final class ColorSwatch: NSControl {
    let color: RGBAColor
    var isChosen = false { didSet { needsDisplay = true } }

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
        NSColor(cgColor: color.cgColor)?.setFill()
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
        sendAction(action, to: target)
    }
}

import AppKit
import KakiireCore

/// ウインドウ右のレイヤー一覧。グループ(図形 → ハイライター → 効果 → 画像)ごとに、前面を上に並べる。
///
/// 変更はすべて EditorWindowController 経由で `EditOperation` にするので、Undo できる。
final class LayerPanel: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let width: CGFloat = 220
    private static let dragType = NSPasteboard.PasteboardType("com.tep-lab.kakiire.layer")

    private enum Item: Equatable {
        case header(RenderGroup)
        case layer(UUID)
    }

    private weak var controller: EditorWindowController?
    private let table = LayerTableView()
    private var items: [Item] = []
    private var syncing = false

    init(controller: EditorWindowController) {
        self.controller = controller
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: String(localized: "レイヤー"))
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("layer"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.registerForDraggedTypes([Self.dragType])
        table.draggingDestinationFeedbackStyle = .gap
        table.onDelete = { [weak self] in self?.controller?.delete(nil) }
        table.setAccessibilityLabel(String(localized: "レイヤー"))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    // MARK: - 中身

    private var document: Document? { controller?.displayedDocument }

    /// 文書が変わったら作り直す。編集中の名前欄があれば、確定させてから。
    func reload() {
        guard let doc = document else { return }
        var next: [Item] = []
        let rows = LayerList.rows(doc)
        for g in RenderGroup.allCases.reversed() {
            let ids = rows.filter { doc.annotation($0)?.content.renderGroup == g }
            if ids.isEmpty { continue }
            next.append(.header(g))
            next += ids.map(Item.layer)
        }
        items = next
        table.reloadData()
        syncSelection()
    }

    /// キャンバスの選択を一覧に映す。
    func syncSelection() {
        guard let controller else { return }
        syncing = true
        defer { syncing = false }
        let rows = IndexSet(items.indices.filter { if case .layer(let id) = items[$0] { controller.selection.contains(id) } else { false } })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { table.scrollRowToVisible(first) }
    }

    private func layerID(at row: Int) -> UUID? {
        guard items.indices.contains(row), case .layer(let id) = items[row] else { return nil }
        return id
    }

    /// 表の行(見出しを含む)から、LayerList の行(見出しを除く)へ。
    private func layerRow(forTableRow row: Int) -> Int {
        items.prefix(row).filter { if case .layer = $0 { true } else { false } }.count
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { layerID(at: row) != nil }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch items[row] {
        case .header(let g):
            let label = NSTextField(labelWithString: g.localizedTitle)
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .tertiaryLabelColor
            return label
        case .layer(let id):
            guard let a = document?.annotation(id) else { return nil }
            let cell = (tableView.makeView(withIdentifier: LayerCell.identifier, owner: nil) as? LayerCell) ?? LayerCell()
            cell.configure(a, editable: !(controller?.isReadOnly ?? true))
            cell.onToggleHidden = { [weak self] in self?.toggle(id, hidden: true) }
            cell.onToggleLocked = { [weak self] in self?.toggle(id, hidden: false) }
            cell.name.delegate = self
            cell.name.tag = row
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing else { return }
        let ids = Set(table.selectedRowIndexes.compactMap(layerID(at:)))
        controller?.selectLayers(ids)
    }

    /// 選択中の行の目・鍵を押したら、選択中のもの全部に当てる。
    private func toggle(_ id: UUID, hidden: Bool) {
        guard let controller, let a = document?.annotation(id) else { return }
        let selected = Set(table.selectedRowIndexes.compactMap(layerID(at:)))
        let targets = selected.contains(id) ? selected : [id]
        if hidden { controller.setLayersHidden(targets, !a.hidden) } else { controller.setLayersLocked(targets, !a.locked) }
    }

    @objc private func doubleClicked() {
        let row = table.clickedRow
        guard layerID(at: row) != nil, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? LayerCell,
              cell.name.isEditable else { return }
        window?.makeFirstResponder(cell.name)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let id = layerID(at: field.tag) else { return }
        controller?.renameLayer(id, field.stringValue)
    }

    // MARK: - ドラッグで並べ替え

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard let id = layerID(at: row), !(controller?.isReadOnly ?? true) else { return nil }
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: Self.dragType)
        return item
    }

    private func draggedID(_ info: any NSDraggingInfo) -> UUID? {
        info.draggingPasteboard.string(forType: Self.dragType).flatMap(UUID.init(uuidString:))
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard op == .above, let id = draggedID(info), let doc = document,
              LayerList.move(id, toRow: layerRow(forTableRow: row), in: doc) != nil else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = draggedID(info) else { return false }
        return controller?.moveLayer(id, toRow: layerRow(forTableRow: row)) ?? false
    }
}

/// Delete キーで選択中のレイヤーを消す。
final class LayerTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// レイヤー1行:目(表示)・鍵(ロック)・種類のアイコン・名前。
final class LayerCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("LayerCell")

    let eye = NSButton()
    let lock = NSButton()
    let icon = NSImageView()
    let name = NSTextField()
    var onToggleHidden: (() -> Void)?
    var onToggleLocked: (() -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        for b in [eye, lock] {
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.imagePosition = .imageOnly
            b.target = self
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 18).isActive = true
        }
        eye.action = #selector(eyeClicked)
        lock.action = #selector(lockClicked)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.contentTintColor = .secondaryLabelColor
        name.isBordered = false
        name.drawsBackground = false
        name.lineBreakMode = .byTruncatingTail
        name.cell?.sendsActionOnEndEditing = true
        name.translatesAutoresizingMaskIntoConstraints = false
        textField = name
        imageView = icon

        let stack = NSStackView(views: [eye, lock, icon, name])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ a: Annotation, editable: Bool) {
        eye.image = NSImage(systemSymbolName: a.hidden ? "eye.slash" : "eye", accessibilityDescription: a.hidden ? String(localized: "表示する") : String(localized: "隠す"))
        eye.contentTintColor = a.hidden ? .tertiaryLabelColor : .secondaryLabelColor
        eye.setAccessibilityLabel(a.hidden ? String(localized: "\(a.name)を表示する") : String(localized: "\(a.name)を隠す"))
        eye.toolTip = a.hidden ? String(localized: "表示する") : String(localized: "隠す(書き出しにも出ない)")
        lock.image = NSImage(systemSymbolName: a.locked ? "lock.fill" : "lock.open", accessibilityDescription: a.locked ? String(localized: "ロック解除") : String(localized: "ロック"))
        lock.contentTintColor = a.locked ? .labelColor : .quaternaryLabelColor
        lock.setAccessibilityLabel(a.locked ? String(localized: "\(a.name)のロックを解除") : String(localized: "\(a.name)をロック"))
        lock.toolTip = a.locked ? String(localized: "ロックを解除する") : String(localized: "ロックする(キャンバスで選べなくなる)")
        toolTip = editable ? String(localized: "ドラッグで重なり順を変える。ダブルクリックで名前を変更") : nil
        eye.isEnabled = editable
        lock.isEnabled = editable
        icon.image = NSImage(systemSymbolName: Self.symbol(a.content), accessibilityDescription: a.content.localizedName)
            ?? NSImage(systemSymbolName: "square.dashed", accessibilityDescription: nil)
        name.stringValue = a.name
        name.isEditable = editable
        name.textColor = a.hidden ? .tertiaryLabelColor : .labelColor
    }

    static func symbol(_ c: AnnotationContent) -> String {
        switch c {
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .obscure(let s): s.mode == .pixelate ? "checkerboard.rectangle" : "drop"
        case .highlighter: "highlighter"
        case .pen: "pencil.tip"
        case .stamp(let s):
            switch s.kind {
            case .number: s.number <= 50 ? "\(s.number).circle" : "number.circle"
            case .letter: s.label.count == 1 ? "\(s.label.lowercased()).circle" : "textformat.abc"
            default: s.kind.sfSymbol
            }
        case .image: "photo"
        case .unknown: "questionmark.square.dashed"
        }
    }

    @objc private func eyeClicked() { onToggleHidden?() }
    @objc private func lockClicked() { onToggleLocked?() }
}

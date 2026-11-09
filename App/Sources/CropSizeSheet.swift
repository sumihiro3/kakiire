import AppKit
import KakiireCore

/// 「切り抜きの範囲を指定…」。左・上・幅・高さを px で入れ、切り抜きツールの範囲にする(確定は Return)。
final class CropSizeSheet: NSObject, NSTextFieldDelegate {
    private let image: CGSize
    private var rect: CGRect
    private let left = NSTextField()
    private let top = NSTextField()
    private let width = NSTextField()
    private let height = NSTextField()
    private let keepAspect = NSButton(checkboxWithTitle: String(localized: "縦横比を固定"), target: nil, action: nil)
    /// 固定する縦横比。シートを開いたときの範囲の比。
    private let aspect: CGSize

    private init(image: CGSize, current: CGRect) {
        self.image = image
        rect = CropMath.fit(current, in: image)
        aspect = rect.size
        super.init()
    }

    /// シートを出し、OK なら画像に収めた範囲で `onApply` を呼ぶ。
    static func run(image: CGSize, current: CGRect, on window: NSWindow, onApply: @escaping (CGRect) -> Void) {
        let sheet = CropSizeSheet(image: image, current: current)
        let alert = NSAlert()
        alert.messageText = String(localized: "切り抜きの範囲")
        alert.informativeText = String(localized: "範囲を px で指定します。画像は \(Int(image.width)) × \(Int(image.height)) px です。Return で切り抜きを確定します。")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: String(localized: "キャンセル"))
        alert.accessoryView = sheet.makeView()
        alert.window.initialFirstResponder = sheet.width
        alert.beginSheetModal(for: window) { r in
            sheet.commitEditing()
            if r == .alertFirstButtonReturn { onApply(CropMath.fit(sheet.rect, in: sheet.image)) }
            _ = sheet
        }
    }

    private func makeView() -> NSView {
        for f in [left, top, width, height] {
            f.delegate = self
            NumberInput.configure(f, minimum: f === left || f === top ? 0 : 1)
        }
        left.setAccessibilityLabel(String(localized: "左"))
        top.setAccessibilityLabel(String(localized: "上"))
        width.setAccessibilityLabel(String(localized: "幅"))
        height.setAccessibilityLabel(String(localized: "高さ"))
        refresh(except: nil)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "左:")), left, NSTextField(labelWithString: "px")],
            [NSTextField(labelWithString: String(localized: "上:")), top, NSTextField(labelWithString: "px")],
            [NSTextField(labelWithString: String(localized: "幅:")), width, NSTextField(labelWithString: "px")],
            [NSTextField(labelWithString: String(localized: "高さ:")), height, NSTextField(labelWithString: "px")],
            [NSGridCell.emptyContentView, keepAspect, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.cell(for: keepAspect)?.xPlacement = .leading
        grid.mergeCells(inHorizontalRange: NSRange(location: 1, length: 2), verticalRange: NSRange(location: 4, length: 1))
        grid.frame = NSRect(x: 0, y: 0, width: 240, height: 140)
        return grid
    }

    private func refresh(except field: NSTextField?) {
        if field !== left { left.integerValue = Int(rect.minX) }
        if field !== top { top.integerValue = Int(rect.minY) }
        if field !== width { width.integerValue = Int(rect.width) }
        if field !== height { height.integerValue = Int(rect.height) }
    }

    private func update(from field: NSTextField) {
        guard let v = NumberInput.parse(field.stringValue), v >= 0 else { return }
        let lock = keepAspect.state == .on
        switch field {
        case left: rect.origin.x = v
        case top: rect.origin.y = v
        case width:
            rect.size.width = v
            if lock { rect.size.height = CropMath.height(forWidth: v, keeping: aspect) }
        default:
            rect.size.height = v
            if lock { rect.size.width = CropMath.width(forHeight: v, keeping: aspect) }
        }
        refresh(except: field)
    }

    private func commitEditing() {
        for f in [left, top, width, height] where f.currentEditor() != nil { update(from: f) }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSTextField { update(from: f) }
    }
}

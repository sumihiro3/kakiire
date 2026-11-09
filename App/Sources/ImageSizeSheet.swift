import AppKit
import KakiireCore

/// 「画像サイズ…」。書き出しの幅・高さ(px)か比率(%)で `outputScale` を決める。縦横比は常に保つ。
///
/// 線や文字も画像と一緒に縮む(ADR 0001)。元画像は書き換えない。
final class ImageSizeSheet: NSObject, NSTextFieldDelegate {
    private let source: CGSize
    private let width = NSTextField()
    private let height = NSTextField()
    private let percent = NSTextField()
    private var scale: Double

    private init(doc: Document) {
        source = doc.effectiveCrop.size
        scale = doc.canvas.outputScale
        super.init()
    }

    /// シートを出し、OK なら新しい倍率で `onApply` を呼ぶ。
    static func run(for doc: Document, on window: NSWindow, onApply: @escaping (Double) -> Void) {
        let sheet = ImageSizeSheet(doc: doc)
        let alert = NSAlert()
        alert.messageText = String(localized: "画像サイズ")
        alert.informativeText = String(localized: "書き出す画像の大きさを変えます。線や文字も同じ比率で縮みます。元の画像は \(Int(sheet.source.width)) × \(Int(sheet.source.height)) px です。")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: String(localized: "キャンセル"))
        alert.accessoryView = sheet.makeView()
        alert.window.initialFirstResponder = sheet.width
        alert.beginSheetModal(for: window) { r in
            // 入力中の欄の値も拾う。
            sheet.commitEditing()
            if r == .alertFirstButtonReturn { onApply(sheet.scale) }
            _ = sheet
        }
    }

    private func makeView() -> NSView {
        for f in [width, height, percent] {
            f.delegate = self
            NumberInput.configure(f, fractionDigits: f === percent ? 1 : 0)
        }
        width.setAccessibilityLabel(String(localized: "幅"))
        height.setAccessibilityLabel(String(localized: "高さ"))
        percent.setAccessibilityLabel(String(localized: "比率"))
        refresh(except: nil)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "幅:")), width, NSTextField(labelWithString: "px")],
            [NSTextField(labelWithString: String(localized: "高さ:")), height, NSTextField(labelWithString: "px")],
            [NSTextField(labelWithString: String(localized: "比率:")), percent, NSTextField(labelWithString: "%")],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.frame = NSRect(x: 0, y: 0, width: 220, height: 90)
        return grid
    }

    private func refresh(except field: NSTextField?) {
        if field !== width { width.integerValue = Int((source.width * scale).rounded()) }
        if field !== height { height.integerValue = Int((source.height * scale).rounded()) }
        if field !== percent { percent.doubleValue = (scale * 1000).rounded() / 10 }
    }

    private func update(from field: NSTextField) {
        guard let v = NumberInput.parse(field.stringValue), v > 0 else { return }
        switch field {
        case width: scale = v / max(source.width, 1)
        case height: scale = v / max(source.height, 1)
        default: scale = v / 100
        }
        scale = clamp(scale, 0.01, 16)
        refresh(except: field)
    }

    private func commitEditing() {
        for f in [width, height, percent] where f.currentEditor() != nil { update(from: f) }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSTextField { update(from: f) }
    }
}

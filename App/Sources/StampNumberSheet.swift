import AppKit
import KakiireCore

/// 「番号を変更…」。数字・英字スタンプの番号を入力で変える。英字スタンプは英字(A, B, … AA)で受ける。
final class StampNumberSheet: NSObject, NSTextFieldDelegate {
    private let kind: StampKind
    private let field = NSTextField()
    private weak var okButton: NSButton?

    private init(kind: StampKind) {
        self.kind = kind
        super.init()
    }

    /// シートを出し、OK なら読めた番号で `onApply` を呼ぶ。読めない入力のあいだは OK を押せない。
    static func run(_ spec: StampSpec, on window: NSWindow, onApply: @escaping (Int) -> Void) {
        let sheet = StampNumberSheet(kind: spec.kind)
        let alert = NSAlert()
        alert.messageText = String(localized: "スタンプの番号")
        alert.informativeText = spec.kind == .letter
            ? String(localized: "A〜ZZZ の英字で入力します。")
            : String(localized: "1〜999 の数字で入力します。")
        sheet.okButton = alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: String(localized: "キャンセル"))
        sheet.field.stringValue = spec.label
        // CLI / MCP では 1000 以上も置けるので、開いた時点で読めない番号なら OK を押せなくしておく。
        sheet.okButton?.isEnabled = sheet.number != nil
        sheet.field.delegate = sheet
        sheet.field.alignment = .center
        sheet.field.frame = NSRect(x: 0, y: 0, width: 80, height: 22)
        sheet.field.setAccessibilityLabel(String(localized: "番号"))
        alert.accessoryView = sheet.field
        alert.window.initialFirstResponder = sheet.field
        alert.beginSheetModal(for: window) { r in
            guard r == .alertFirstButtonReturn, let n = sheet.number else { return }
            onApply(n)
        }
    }

    private var number: Int? { StampSpec.number(fromLabel: field.stringValue, kind: kind) }

    func controlTextDidChange(_ obj: Notification) {
        okButton?.isEnabled = number != nil
    }
}

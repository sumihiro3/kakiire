import AppKit
import KakiireCore

/// テキスト注釈をキャンバス上で直接編集する。注釈の位置に NSTextView を重ね、確定時に結果を返す。
///
/// キャンバスは画像ピクセル座標なので、フォントサイズをそのまま渡せば拡大率に合わせて見える大きさも揃う。
final class TextEditing: NSObject, NSTextViewDelegate {
    struct Result {
        let id: UUID
        let isNew: Bool
        let spec: TextSpec
    }

    private var textView: NSTextView?
    private var spec: TextSpec?
    private var isNew = false
    private var onEnd: ((Result) -> Void)?
    private(set) var annotationID: UUID?

    var isEditing: Bool { textView != nil }

    func begin(spec: TextSpec, id: UUID, isNew: Bool, in host: NSView, onEnd: @escaping (Result) -> Void) {
        end()
        self.spec = spec
        self.isNew = isNew
        self.onEnd = onEnd
        annotationID = id

        let pad = TextLayout.padding(spec)
        let tv = NSTextView(frame: NSRect(x: spec.origin.x + pad, y: spec.origin.y + pad, width: 40, height: CGFloat(spec.fontSize) * 1.3))
        tv.font = .systemFont(ofSize: CGFloat(spec.fontSize), weight: spec.bold ? .bold : .regular)
        tv.textColor = NSColor(cgColor: spec.color.cgColor)
        tv.insertionPointColor = NSColor(cgColor: spec.color.cgColor) ?? .labelColor
        tv.string = spec.text
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        host.addSubview(tv)
        textView = tv
        fit()
        tv.window?.makeFirstResponder(tv)
        tv.selectAll(nil)
    }

    /// 編集を確定する。
    func end() {
        guard let tv = textView, var s = spec, let id = annotationID else { return }
        s.text = tv.string
        let cb = onEnd
        textView = nil
        spec = nil
        annotationID = nil
        onEnd = nil
        tv.removeFromSuperview()
        cb?(Result(id: id, isNew: isNew, spec: s))
    }

    /// 編集中の文字の色・大きさ・袋文字を変える。確定時の結果にも残る。
    func restyle(_ transform: (TextSpec) -> TextSpec) {
        guard let tv = textView, let old = spec else { return }
        let s = transform(old)
        spec = s
        tv.font = .systemFont(ofSize: CGFloat(s.fontSize), weight: s.bold ? .bold : .regular)
        tv.textColor = NSColor(cgColor: s.color.cgColor)
        tv.insertionPointColor = NSColor(cgColor: s.color.cgColor) ?? .labelColor
        fit()
    }

    private func fit() {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).size
        let font = tv.font ?? .systemFont(ofSize: 20)
        tv.setFrameSize(NSSize(width: max(used.width + font.pointSize * 0.6, font.pointSize),
                               height: max(used.height, font.pointSize * 1.2)))
    }

    func textDidChange(_ notification: Notification) { fit() }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Esc と ⌘Return で確定。Return は改行のまま。
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            end()
            return true
        }
        return false
    }

    func textDidEndEditing(_ notification: Notification) { end() }
}

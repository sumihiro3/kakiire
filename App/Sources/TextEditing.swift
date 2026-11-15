import AppKit
import KakiireCore

/// テキストと吹き出しの文字をキャンバス上で直接編集する。文字の位置に NSTextView を重ね、確定時に結果を返す。
///
/// キャンバスは画像ピクセル座標なので、フォントサイズをそのまま渡せば拡大率に合わせて見える大きさも揃う。
/// 吹き出しは入力欄の背景を透明にし、下に描く吹き出し(`editingBubble`)を打った文字に合わせて伸ばす。
final class TextEditing: NSObject, NSTextViewDelegate {
    struct Result {
        let id: UUID
        let isNew: Bool
        /// `.text` か `.bubble`。文字は入力欄のものに置き換えてある。
        let content: AnnotationContent
    }

    private var textView: NSTextView?
    private var content: AnnotationContent?
    private var isNew = false
    private var onEnd: ((Result) -> Void)?
    /// 打つたびに呼ぶ(吹き出しの描き直しのため)。引数は変わる前と後の描画範囲。
    private var onChange: ((CGRect) -> Void)?
    private(set) var annotationID: UUID?

    var isEditing: Bool { textView != nil }

    /// 編集中の吹き出し(入力欄の文字を反映したもの)。テキストの編集中は nil。
    var editingBubble: BubbleSpec? {
        guard case .bubble(var b) = content, let tv = textView else { return nil }
        b.text = tv.string
        return b
    }

    /// 編集中の中身の文字の部分。
    private static func textSpec(_ c: AnnotationContent) -> TextSpec? {
        switch c {
        case .text(let t): t
        case .bubble(let b): b.textSpec
        default: nil
        }
    }

    /// `.text` か `.bubble` を編集する。それ以外は何もしない。
    func begin(content: AnnotationContent, id: UUID, isNew: Bool, in host: NSView,
               onChange: ((CGRect) -> Void)? = nil, onEnd: @escaping (Result) -> Void) {
        end()
        guard let spec = Self.textSpec(content) else { return }
        self.content = content
        self.isNew = isNew
        self.onEnd = onEnd
        self.onChange = onChange
        annotationID = id

        let pad = TextLayout.padding(spec)
        let tv = NSTextView(frame: NSRect(x: spec.origin.x + pad, y: spec.origin.y + pad, width: 40, height: CGFloat(spec.fontSize) * 1.3))
        tv.string = spec.text
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
        textView = tv
        apply(spec)
        host.addSubview(tv)
        fit()
        lastBounds = changedBounds()
        tv.window?.makeFirstResponder(tv)
        tv.selectAll(nil)
    }

    /// 編集を確定する。
    func end() {
        guard let tv = textView, let c = content, let id = annotationID else { return }
        let cb = onEnd
        textView = nil
        content = nil
        annotationID = nil
        onEnd = nil
        onChange = nil
        lastBounds = .null
        tv.removeFromSuperview()
        cb?(Result(id: id, isNew: isNew, content: Self.replacingText(c, with: tv.string)))
    }

    private static func replacingText(_ c: AnnotationContent, with s: String) -> AnnotationContent {
        switch c {
        case .text(var t): t.text = s; return .text(t)
        case .bubble(var b): b.text = s; return .bubble(b)
        default: return c
        }
    }

    /// 編集中の文字の色・大きさ・袋文字・吹き出しの形を変える。確定時の結果にも残る。
    func restyle(_ transform: (AnnotationContent) -> AnnotationContent) {
        guard let tv = textView, let old = content else { return }
        let c = transform(Self.replacingText(old, with: tv.string))
        content = c
        if let s = Self.textSpec(c) { apply(s) }
        fit()
        changed()
    }

    /// 文字の見た目を入力欄に映す。吹き出しは塗りの上に打つので背景を描かない。
    private func apply(_ spec: TextSpec) {
        guard let tv = textView else { return }
        let isBubble = if case .bubble = content { true } else { false }
        tv.font = .systemFont(ofSize: CGFloat(spec.fontSize), weight: spec.bold ? .bold : .regular)
        tv.textColor = NSColor(cgColor: spec.color.cgColor)
        tv.insertionPointColor = NSColor(cgColor: spec.color.cgColor) ?? .labelColor
        tv.drawsBackground = !isBubble
        tv.backgroundColor = NSColor.white.withAlphaComponent(0.6)
    }

    /// 吹き出しの描画範囲(テキストは入力欄が自分で描くので空)。
    private func changedBounds() -> CGRect {
        editingBubble.map(BubbleLayout.bounds) ?? .null
    }

    private func fit() {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).size
        let font = tv.font ?? .systemFont(ofSize: 20)
        tv.setFrameSize(NSSize(width: max(used.width + font.pointSize * 0.6, font.pointSize),
                               height: max(used.height, font.pointSize * 1.2)))
    }

    private var lastBounds: CGRect = .null

    func textDidChange(_ notification: Notification) {
        fit()
        changed()
    }

    private func changed() {
        let now = changedBounds()
        onChange?(lastBounds.union(now))
        lastBounds = now
    }

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

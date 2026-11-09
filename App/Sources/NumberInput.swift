import AppKit

/// 数値の入力欄の読み方。シートで共通に使う。
enum NumberInput {
    /// 入力中の文字列を数値として読む。入力中は formatter を通らないので文字列から読む。
    /// 日本語入力のままだと全角になるので半角に直し、桁区切りは外す。
    static func parse(_ text: String) -> Double? {
        let half = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: ",", with: "")
        return Double(half)
    }

    /// 右寄せで、`fractionDigits` 桁までの数を受け付ける欄に整える。
    static func configure(_ f: NSTextField, fractionDigits: Int = 0, minimum: Double = 1, width: CGFloat = 80) {
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = fractionDigits
        fmt.minimum = NSNumber(value: minimum)
        f.formatter = fmt
    }
}
